data "aws_caller_identity" "current" {}

# AMI oficial mais recente do Amazon Linux 2023, via parâmetro público do
# SSM mantido pela própria AWS — evita filtro manual por nome/data.
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Rede default da conta: usada só para dar um lugar de existir às instâncias
# de exemplo. Redes dedicadas (VPC própria, subnets privadas) são assunto
# dos capítulos 09/10 — aqui a rede é só coadjuvante.
data "aws_vpc" "default" {
  count   = var.subnet_id == "" ? 1 : 0
  default = true
}

# Nem toda AZ do us-east-1 suporta todo tipo de instância (o mapeamento de
# AZ é por conta, e AZs mais antigas às vezes ficam de fora de tipos mais
# novos como t3.micro) — descobrir as AZs que suportam var.instance_type
# antes de escolher a subnet evita um RunInstances que falha por sorteio.
data "aws_ec2_instance_type_offerings" "supported" {
  count = var.subnet_id == "" ? 1 : 0

  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }

  location_type = "availability-zone"
}

data "aws_subnets" "default" {
  count = var.subnet_id == "" ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }

  filter {
    name   = "availability-zone"
    values = data.aws_ec2_instance_type_offerings.supported[0].locations
  }
}

locals {
  subnet_id = var.subnet_id != "" ? var.subnet_id : data.aws_subnets.default[0].ids[0]
}

# Instâncias "de negócio" que representam a aplicação (checkout) que o time
# de plantão precisa reiniciar quando ela trava. Não rodam nada (AMI padrão,
# sem user_data) — existem só para dar ARNs concretos à policy. Sem IP
# público: este laboratório não precisa que elas sejam alcançáveis pela
# internet.
resource "aws_instance" "checkout_app" {
  for_each = toset(var.checkout_app_instance_names)

  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = local.subnet_id
  associate_public_ip_address = false

  tags = merge(var.tags, {
    Name = each.key
  })
}

# Policy least-privilege: só as actions que o plantão realmente precisa.
#
# ec2:DescribeInstances não suporta permissão a nível de recurso — é uma
# limitação documentada da própria API do EC2 (Service Authorization
# Reference), não descuido do exemplo: essa statement precisa de
# "Resource": "*". Já start/stop/reboot suportam escopo por ARN, então
# ficam presas só às instâncias do checkout. Comparar com o "antes"
# documentado no README (AdministratorAccess anexado direto ao usuário).
data "aws_iam_policy_document" "oncall_sysops" {
  statement {
    sid       = "DescribeEC2Instances"
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }

  statement {
    sid    = "RestartCheckoutAppInstances"
    effect = "Allow"
    actions = [
      "ec2:StartInstances",
      "ec2:StopInstances",
      "ec2:RebootInstances",
    ]
    resources = [for instance in aws_instance.checkout_app : instance.arn]
  }
}

resource "aws_iam_policy" "oncall_sysops" {
  name        = "insecurity-inc-oncall-sysops-policy"
  description = "Describe amplo (limitação da API do EC2) + start/stop/reboot só nas instâncias do checkout — least privilege para o plantão de sysops."
  policy      = data.aws_iam_policy_document.oncall_sysops.json
  tags        = var.tags
}

# RBAC: a policy é anexada ao GRUPO, nunca diretamente a um usuário
# (CIS AWS Foundations Benchmark v3.0.0, controle 1.15).
resource "aws_iam_group" "oncall_sysops" {
  name = "insecurity-inc-oncall-sysops"
}

resource "aws_iam_group_policy_attachment" "oncall_sysops" {
  group      = aws_iam_group.oncall_sysops.name
  policy_arn = aws_iam_policy.oncall_sysops.arn
}

# Usuário representando o analista de plantão. Sem login de console e sem
# access key geradas por Terraform: credencial de longo prazo não deve viver
# no state. Provisionamento de credencial (ou, melhor, SSO via IAM Identity
# Center) fica fora do escopo deste capítulo — o foco aqui é a estrutura de
# permissões (RBAC), não o ciclo de vida da credencial.
resource "aws_iam_user" "oncall_analyst" {
  name = var.oncall_user_name
  tags = var.tags
}

resource "aws_iam_user_group_membership" "oncall_analyst" {
  user   = aws_iam_user.oncall_analyst.name
  groups = [aws_iam_group.oncall_sysops.name]
}
