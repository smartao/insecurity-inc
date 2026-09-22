data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# ---------------------------------------------------------------------------
# A VPC do laboratório
# ---------------------------------------------------------------------------

# VPC dedicada (não a padrão da conta), para o capítulo poder ser destruído
# sem deixar rastro -- mesmo motivo do capítulo 09. Diferença: aqui a subnet é
# PÚBLICA (internet gateway + rota 0.0.0.0/0). Não é para o `terraform apply`
# em si -- sozinho, ele não cria nenhuma instância e não gera nenhum tráfego
# real, então o flow log fica sem registro nenhum (ver README, "Como testar",
# e a "Limitação deliberada" do capítulo 09, que vale igual aqui). A rota
# pública existe só para o teste opcional (README) alcançar, da internet, a
# instância criada e destruída ali mesmo -- fora do `terraform apply`.
resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "insecurity-inc-lab" })
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = merge(var.tags, { Name = "insecurity-inc-lab" })
}

resource "aws_subnet" "lab" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(var.tags, { Name = "insecurity-inc-lab" })
}

resource "aws_route_table" "lab" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }

  tags = merge(var.tags, { Name = "insecurity-inc-lab" })
}

resource "aws_route_table_association" "lab" {
  subnet_id      = aws_subnet.lab.id
  route_table_id = aws_route_table.lab.id
}

# Hábito herdado do capítulo 09, não o assunto deste: toda VPC nova nasce com
# um default security group liberando tudo entre membros e toda a saída (CIS
# v5.0.0, 5.5). Zerado aqui do mesmo jeito -- ver 09 para a explicação
# completa (inclusive a pegadinha de precisar do ingress/egress = [] EXPLÍCITO
# para o Terraform virar autoritativo sobre o grupo).
resource "aws_default_security_group" "lab" {
  vpc_id = aws_vpc.lab.id

  ingress = []
  egress  = []

  tags = merge(var.tags, { Name = "insecurity-inc-lab-default-nao-usar" })
}

# ---------------------------------------------------------------------------
# Para onde os flow logs vão: um log group dedicado
# ---------------------------------------------------------------------------

# Criptografado em repouso por padrão com a chave gerenciada da AWS (todo log
# group do CloudWatch Logs é) -- sem CMK própria aqui: seria mais um recurso
# cobrando ~US$1/mês (capítulo 06) num capítulo que o roadmap marca como 🟢.
# Ver README, Dívidas em aberto.
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/insecurity-inc/vpc-flow-logs"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, { Name = "insecurity-inc-vpc-flow-logs" })
}

# ---------------------------------------------------------------------------
# O papel que o serviço de flow logs assume para publicar no log group -- e só
# nele
# ---------------------------------------------------------------------------

# A condição aws:SourceAccount + aws:SourceArn é a proteção contra o
# "confused deputy" que a própria documentação da AWS recomenda -- e que o
# exemplo de referência dela (a política mínima, citada no README) não inclui.
# O ID do flow log só existe depois de criado, então o SourceArn usa um
# curinga na posição do ID: é exatamente o que a documentação sugere para esse
# caso ("If you don't know the flow log ID, you can replace that portion of
# the ARN with a wildcard").
resource "aws_iam_role" "flow_logs" {
  name = "insecurity-inc-vpc-flow-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:vpc-flow-log/*" }
      }
    }]
  })

  tags = merge(var.tags, { Name = "insecurity-inc-vpc-flow-logs" })
}

# Mais estreita que a política de referência da AWS, que usa Resource "*":
# aqui só as ações que o serviço precisa para ESCREVER num log group que o
# Terraform já criou e já é dono -- sem logs:CreateLogGroup (não é o flow log
# que decide se o grupo existe) e com o Resource travado num grupo só, o
# mesmo espírito de least privilege do capítulo 01.
#
# Pegadinha testada nesta conta, e na direção OPOSTA à intuição: a API bruta
# do CloudWatch Logs (describe-log-groups) devolve o ARN do grupo com ":*" no
# final, mas o atributo `arn` do próprio recurso `aws_cloudwatch_log_group`
# no Terraform vem SEM esse sufixo (conferido no state: os dois valores
# divergem para o mesmo grupo). Sem o ":*" aqui, o Resource vira um ARN exato
# de log group -- que não cobre os log streams (um por interface de rede) que
# logs:CreateLogStream/PutLogEvents/DescribeLogStreams precisam enxergar por
# baixo dele -- e o papel fica sem permissão de verdade, em silêncio: o
# `aws_flow_log` é criado do mesmo jeito (ele não valida a permissão na
# criação), só a entrega dos registros é que falharia (passo 5 de Como
# testar). Por isso o ":*" abaixo é adicionado à mão.
resource "aws_iam_role_policy" "flow_logs" {
  name = "insecurity-inc-vpc-flow-logs-publish"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
      ]
      Resource = "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"
    }]
  })
}

# ---------------------------------------------------------------------------
# O flow log em si -- nível VPC, tráfego ALL, formato personalizado
# ---------------------------------------------------------------------------

resource "aws_flow_log" "vpc" {
  vpc_id                   = aws_vpc.lab.id
  traffic_type             = var.traffic_type
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.vpc_flow_logs.arn
  iam_role_arn             = aws_iam_role.flow_logs.arn
  max_aggregation_interval = var.max_aggregation_interval

  # Formato personalizado, além do padrão (os 14 campos da versão 2): junta
  # identificação de VPC/subnet/instância (versão 3), a direção do fluxo e os
  # dois endereços de PACOTE (versão 5, úteis atrás de um NAT gateway ou
  # load balancer, onde o endereço da interface não é o endereço real de quem
  # originou o tráfego) e as flags TCP (versão 3). É o que permite responder
  # não só "aceitou ou rejeitou", mas "em que direção, com que flags, e para
  # qual IP de verdade" -- ver README, Correção.
  #
  # Pegadinha: dentro de uma string do Terraform, "${" abre interpolação --
  # "$${" é como se escreve um "${" literal, e "${nome-do-campo}" é a sintaxe
  # que os nomes de campo do flow log usam.
  log_format = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status} $${vpc-id} $${subnet-id} $${instance-id} $${type} $${flow-direction} $${pkt-srcaddr} $${pkt-dstaddr} $${tcp-flags}"

  tags = merge(var.tags, { Name = "insecurity-inc-vpc-flow-log" })

  # O IAM é eventualmente consistente: sem essa dependência explícita, nada
  # impede o flow log de ser criado antes da política de permissão terminar
  # de propagar, e as primeiras tentativas de entrega falhariam em silêncio
  # (a AWS tenta de novo sozinha, mas não há razão para arriscar).
  depends_on = [aws_iam_role_policy.flow_logs]
}
