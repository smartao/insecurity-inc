data "aws_caller_identity" "current" {}

# AMI oficial mais recente do Amazon Linux 2023, via parâmetro público do
# SSM mantido pela própria AWS — evita filtro manual por nome/data.
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Rede default da conta: usada só para dar um lugar de existir às instâncias
# de exemplo. Redes dedicadas (VPC própria, subnets privadas) são assunto
# dos capítulos 09/10 — aqui a rede é só coadjuvante (mesmo racional do
# capítulo 01).
data "aws_vpc" "default" {
  count   = var.subnet_id == "" ? 1 : 0
  default = true
}

# Nem toda AZ do us-east-1 suporta todo tipo de instância — descobrir as AZs
# que suportam var.instance_type antes de escolher a subnet evita um
# RunInstances que falha por sorteio.
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

  # Nome da tag usada tanto no principal (IAM User) quanto no recurso (EC2
  # instance). É o "elo" entre identidade e recurso que faz a ABAC
  # funcionar — mantenha o mesmo nome ao taguear identidades e apps novas.
  access_tag_key = "access-project"
}

# Uma instância "de app" por time de exemplo. Não roda nada (AMI padrão, sem
# user_data) — existe só para dar um recurso real e tagueado à policy. Ao
# contrário do capítulo 01 (ARN de cada instância escrito na policy), aqui o
# que importa é a tag access-project no RECURSO — a policy nunca menciona um
# time ou um ARN de instância específico.
resource "aws_instance" "team_app" {
  for_each = toset(var.teams)

  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = local.subnet_id
  associate_public_ip_address = false

  tags = merge(var.tags, {
    Name                   = "insecurity-inc-${each.value}-app"
    (local.access_tag_key) = each.value
  })
}

# Policy única e dinâmica: nenhuma statement referencia um time ou um ARN de
# instância específico.
#
# ec2:DescribeInstances continua exigindo Resource "*" — a mesma limitação
# de API do capítulo 01 (Service Authorization Reference), não descuido do
# exemplo.
#
# Start/Stop/Reboot escopam para o tipo de recurso "instance" da própria
# conta/região e usam uma condition StringEquals comparando a tag do RECURSO
# (aws:ResourceTag) com a tag do PRINCIPAL (aws:PrincipalTag) — é o padrão de
# ABAC por resource tag do tutorial oficial da AWS, aplicado ao EC2. A
# condition Null é a mesma mitigação recomendada pelo tutorial: sem a tag no
# principal, a AWS nega o acesso em vez de resolver a comparação de forma
# imprevisível.
data "aws_iam_policy_document" "abac_team_apps" {
  statement {
    sid       = "DescribeEC2Instances"
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }

  statement {
    sid    = "RestartOwnProjectInstanceOnly"
    effect = "Allow"
    actions = [
      "ec2:StartInstances",
      "ec2:StopInstances",
      "ec2:RebootInstances",
    ]
    resources = ["arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${local.access_tag_key}"
      values   = ["$${aws:PrincipalTag/${local.access_tag_key}}"]
    }

    condition {
      test     = "Null"
      variable = "aws:PrincipalTag/${local.access_tag_key}"
      values   = ["false"]
    }
  }
}

resource "aws_iam_policy" "abac_team_apps" {
  name        = "insecurity-inc-abac-team-apps-policy"
  description = "Describe amplo (limitação da API do EC2) + start/stop/reboot só na instância cuja tag access-project bate com a do principal (ABAC)."
  policy      = data.aws_iam_policy_document.abac_team_apps.json
  tags        = var.tags
}

# RBAC continua presente por baixo da ABAC: a policy é anexada ao GRUPO,
# nunca diretamente a um usuário (CIS AWS Foundations Benchmark v3.0.0,
# controle 1.15) — ABAC substitui a explosão de POLICIES por time, não a
# estrutura de grupos.
resource "aws_iam_group" "abac_analysts" {
  name = "insecurity-inc-abac-analysts"
}

resource "aws_iam_group_policy_attachment" "abac_analysts" {
  group      = aws_iam_group.abac_analysts.name
  policy_arn = aws_iam_policy.abac_team_apps.arn
}

# Um usuário de exemplo por time, todos no MESMO grupo, com a MESMA policy —
# o que muda de um time para o outro é só o valor da tag access-project.
# Sem login de console e sem access key geradas por Terraform (mesmo
# racional do capítulo 01: credencial de longo prazo não deve viver no
# state).
resource "aws_iam_user" "team_analyst" {
  for_each = toset(var.teams)

  name = "insecurity-inc-${each.value}-analyst"

  tags = merge(var.tags, {
    (local.access_tag_key) = each.value
  })
}

resource "aws_iam_user_group_membership" "team_analyst" {
  for_each = toset(var.teams)

  user   = aws_iam_user.team_analyst[each.value].name
  groups = [aws_iam_group.abac_analysts.name]
}
