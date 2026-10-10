data "aws_availability_zones" "available" {
  state = "available"
}

# ---------------------------------------------------------------------------
# A VPC do laboratório
# ---------------------------------------------------------------------------

# Sem internet gateway, sem NAT e sem instâncias: este capítulo trata das
# REGRAS de rede. Camadas de rede (subnets públicas/privadas, rotas) são o
# assunto de SEC05-BP01, um capítulo à parte; aqui existe uma subnet só, para
# ter onde pendurar as interfaces de rede de exemplo. Consequência honesta:
# nada neste laboratório é alcançável pela internet, com ou sem 0.0.0.0/0 nas
# regras -- o que o capítulo prova são as regras, não tráfego real (ver README,
# "Limitação deliberada").
resource "aws_vpc" "lab" {
  cidr_block = var.vpc_cidr

  tags = merge(var.tags, { Name = "insecurity-inc-lab" })
}

# Toda VPC nasce com um security group chamado "default": libera TUDO entre os
# recursos que o usam e TUDO de saída, e é o que qualquer recurso lançado sem
# security group explícito recebe. Não dá para apagá-lo (Client.CannotDelete),
# mas dá para esvaziá-lo -- e é o que o CIS AWS Foundations Benchmark pede
# (v5.0.0, 5.5; Security Hub EC2.2).
#
# Este recurso "adota" o default SG existente da VPC e, na primeira vez que
# assume o controle, remove todas as regras dele. Mas só isso: sem os atributos
# ingress e egress na configuração, o provider os trata como "computados" e
# nunca mais olha para eles -- testado: uma regra 0.0.0.0/0 criada por fora
# NÃO aparecia no plan, e o apply não a removia. Os dois "= []" explícitos são
# o que torna o Terraform autoritativo aqui: qualquer regra que apareça no
# default SG vira deriva, e o próximo apply a remove. Diferente dos três
# security groups abaixo (regras em recursos separados, que o Terraform não
# enxerga se alguém acrescentar uma por fora) -- ver README, passos 3 e 4 de
# Como testar.
resource "aws_default_security_group" "lab" {
  vpc_id = aws_vpc.lab.id

  ingress = []
  egress  = []

  tags = merge(var.tags, { Name = "insecurity-inc-lab-default-nao-usar" })
}

resource "aws_subnet" "lab" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = merge(var.tags, { Name = "insecurity-inc-lab" })
}

# ---------------------------------------------------------------------------
# Um security group por camada -- não um para todo mundo
# ---------------------------------------------------------------------------

# Atenção às descrições, aqui e nas regras: o EC2 só aceita a-z, A-Z, 0-9,
# espaço e ._-:/()#,@[]+=;{}!$* -- sem acento nem cedilha, mesmo num repositório
# em português. E "description" (assim como name e vpc_id) força a recriação do
# security group se mudar depois: um grupo em uso por uma interface de rede não
# pode ser apagado, então a troca exige cuidado (o provider sugere
# create_before_destroy).

resource "aws_security_group" "web" {
  name        = "insecurity-inc-checkout-web"
  description = "Camada web do checkout - unica que aceita trafego da internet, so HTTPS"
  vpc_id      = aws_vpc.lab.id

  tags = merge(var.tags, { Name = "insecurity-inc-checkout-web" })
}

resource "aws_security_group" "app" {
  name        = "insecurity-inc-checkout-app"
  description = "Camada app do checkout - so aceita trafego vindo da camada web"
  vpc_id      = aws_vpc.lab.id

  tags = merge(var.tags, { Name = "insecurity-inc-checkout-app" })
}

resource "aws_security_group" "db" {
  name        = "insecurity-inc-checkout-db"
  description = "Camada de banco do checkout - so aceita trafego vindo da camada app"
  vpc_id      = aws_vpc.lab.id

  tags = merge(var.tags, { Name = "insecurity-inc-checkout-db" })
}

# ---------------------------------------------------------------------------
# As regras -- um recurso por regra, sempre por referência de SG entre camadas
# ---------------------------------------------------------------------------

# Regras em recursos separados (aws_vpc_security_group_*_rule), não em blocos
# ingress/egress dentro do aws_security_group, por dois motivos: (1) a web
# referencia a app na saída e a app referencia a web na entrada -- com regras
# inline isso vira um ciclo de dependência que o Terraform não resolve; (2)
# cada regra ganha um ID (sgr-...) e tags próprios. O custo é a "cegueira"
# documentada no README: uma regra criada por fora não aparece no plan.
# Nunca misturar os dois estilos no mesmo security group (o provider avisa:
# conflitos e diferenças perpétuas).
#
# Um security group só tem regras de PERMISSÃO (não existe "deny") e é
# stateful: a resposta a uma conexão permitida volta sozinha, sem regra de
# retorno. O Terraform remove a regra de saída "libera tudo" que a AWS cria
# junto com todo security group novo -- então, sem uma egress_rule, o grupo não
# sai para lugar nenhum. Ao contrário do "default" acima, é o que queremos.

# --- Camada web: a única porta aberta para a internet do capítulo inteiro ---

resource "aws_vpc_security_group_ingress_rule" "web_https_from_internet" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS da internet - unica regra publica do capitulo"

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = "0.0.0.0/0"

  tags = merge(var.tags, { Name = "web-https-from-internet" })
}

resource "aws_vpc_security_group_egress_rule" "web_to_app" {
  security_group_id = aws_security_group.web.id
  description       = "Encaminha para a camada app, so na porta da aplicacao"

  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.app.id

  tags = merge(var.tags, { Name = "web-to-app" })
}

# --- Camada app: só a web entra; só o banco (e HTTPS) saem ---

resource "aws_vpc_security_group_ingress_rule" "app_from_web" {
  security_group_id = aws_security_group.app.id
  description       = "Porta da aplicacao, so vinda da camada web"

  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.web.id

  tags = merge(var.tags, { Name = "app-from-web" })
}

resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  security_group_id = aws_security_group.app.id
  description       = "Porta do banco, so para a camada de banco"

  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  referenced_security_group_id = aws_security_group.db.id

  tags = merge(var.tags, { Name = "app-to-db" })
}

# Concessão consciente, não descuido: a aplicação precisa chamar APIs da AWS
# (o Secrets Manager do capítulo 08, por exemplo), e um security group filtra
# por IP e porta -- não por nome de host. Restringir isso de verdade exige
# VPC endpoints (uma regra por referência de SG, como as de cima) ou um
# firewall de DNS/de rede, assunto de outros capítulos. Ver README, "Dívidas em
# aberto".
resource "aws_vpc_security_group_egress_rule" "app_https_out" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS de saida para APIs da AWS - ver README, dividas em aberto"

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = "0.0.0.0/0"

  tags = merge(var.tags, { Name = "app-https-out" })
}

# --- Camada de banco: só a app entra; nada sai ---

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id = aws_security_group.db.id
  description       = "Porta do banco, so vinda da camada app"

  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  referenced_security_group_id = aws_security_group.app.id

  tags = merge(var.tags, { Name = "db-from-app" })
}

# De propósito, nenhuma regra de saída no db: um banco não inicia conexões, e
# a resposta às conexões da app volta sozinha (stateful). Repare que não existe
# regra de porta 22 em NENHUM dos três grupos -- ver README, Correção, ponto 4.

# ---------------------------------------------------------------------------
# Interfaces de rede de exemplo -- uma por camada
# ---------------------------------------------------------------------------

# Security group é associado a uma interface de rede (ENI), não a "uma
# máquina". Estas três ENIs, sem instância nenhuma, existem só para que os
# grupos tenham algo a que estar associados -- e para o teste opcional de
# alcançabilidade do README (Reachability Analyzer aceita ENIs como origem e
# destino). ENIs sem instância não aparecem entre os componentes cobrados na
# documentação de preços do VPC.
resource "aws_network_interface" "web" {
  subnet_id       = aws_subnet.lab.id
  security_groups = [aws_security_group.web.id]
  description     = "Placeholder da camada web do checkout (sem instancia) - capitulo 09"

  tags = merge(var.tags, { Name = "insecurity-inc-checkout-web" })
}

resource "aws_network_interface" "app" {
  subnet_id       = aws_subnet.lab.id
  security_groups = [aws_security_group.app.id]
  description     = "Placeholder da camada app do checkout (sem instancia) - capitulo 09"

  tags = merge(var.tags, { Name = "insecurity-inc-checkout-app" })
}

resource "aws_network_interface" "db" {
  subnet_id       = aws_subnet.lab.id
  security_groups = [aws_security_group.db.id]
  description     = "Placeholder da camada de banco do checkout (sem instancia) - capitulo 09"

  tags = merge(var.tags, { Name = "insecurity-inc-checkout-db" })
}
