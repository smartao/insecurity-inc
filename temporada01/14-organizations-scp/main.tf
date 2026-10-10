# ---------------------------------------------------------------------------
# A Organization já existe de verdade -- é pré-requisito deste capítulo, não
# algo que ele cria (ver README, Como aplicar). Por isso é só "data", nunca
# "resource": um resource Terraform acha que é dono do ciclo de vida inteiro,
# incluindo destroy -- e um "aws_organizations_organization" resource
# importado, destruído depois que a conta-membro sai da OU, chama
# DeleteOrganization de verdade (API real, exige só a management account
# sobrando). Foi assim que uma sessão anterior deste capítulo apagou a
# Organization inteira (e o IAM Identity Center com ela) só testando o
# "Como destruir" -- ver README, Nota de incidente. Ligar
# SERVICE_CONTROL_POLICY no Root é, pelo mesmo motivo, pré-requisito manual
# (CLI/Console -- ver README), não Terraform: é o único atributo que
# existiria nesse resource, e não vale o risco de voltar a modelar a
# Organization como algo destruível.
# ---------------------------------------------------------------------------

data "aws_organizations_organization" "this" {}

# ---------------------------------------------------------------------------
# OU que recebe as contas-membro. A SCP é anexada nela, não no Root --
# assim o efeito fica contido na conta nova, sem alcançar a management
# account (que continua direto sob o Root).
# ---------------------------------------------------------------------------

resource "aws_organizations_organizational_unit" "workloads" {
  name      = var.ou_name
  parent_id = data.aws_organizations_organization.this.roots[0].id
  tags      = var.tags
}

# aws_organizations_account só sabe criar conta nova (CreateAccount) -- esta
# conta já existia e foi convidada, então o resource aqui só adota o que já
# existe (import) para poder mover ela pra dentro da OU. iam_user_access_to_billing
# e role_name nunca voltam da API depois da criação (limitação documentada
# do provider) -- declarar/arrastar esses atributos faria o Terraform achar
# divergência e tentar recriar a conta (ForceNew), por isso ignore_changes.
resource "aws_organizations_account" "member" {
  name      = var.member_account_name
  email     = var.member_account_email
  parent_id = aws_organizations_organizational_unit.workloads.id
  tags      = var.tags

  lifecycle {
    ignore_changes = [iam_user_access_to_billing, role_name]
  }
}

# ---------------------------------------------------------------------------
# SCP com 4 guardrails que nenhuma IAM policy dentro da conta-membro
# consegue contornar -- a diferença entre "a conta nova decidiu seguir a
# lição" e "a organização obriga, independente da conta decidir".
#
# DenyRootUser bloqueia qualquer ação do usuário root da conta-membro,
# inclusive as poucas tarefas que só o root pode fazer (ex.: fechar a
# conta, mudar plano de suporte) -- trade-off documentado pela própria AWS
# neste exemplo canônico de SCP (ver README, Dívidas em aberto).
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "baseline_guardrails" {
  statement {
    sid       = "DenyLeaveOrganization"
    effect    = "Deny"
    actions   = ["organizations:LeaveOrganization"]
    resources = ["*"]
  }

  statement {
    sid    = "DenyCloudTrailTamper"
    effect = "Deny"
    actions = [
      "cloudtrail:StopLogging",
      "cloudtrail:DeleteTrail",
      "cloudtrail:UpdateTrail",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyConfigTamper"
    effect = "Deny"
    actions = [
      "config:StopConfigurationRecorder",
      "config:DeleteConfigurationRecorder",
      "config:DeleteDeliveryChannel",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "DenyRootUser"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:root"]
    }
  }
}

resource "aws_organizations_policy" "baseline_guardrails" {
  name        = "insecurity-inc-baseline-guardrails"
  description = "Guardrails mínimos que toda conta-membro da organização herda, independente do que a conta local configure: não sair da organização, não desligar CloudTrail/Config, não agir como root."
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.baseline_guardrails.json
  tags        = var.tags
}

resource "aws_organizations_policy_attachment" "workloads" {
  policy_id = aws_organizations_policy.baseline_guardrails.id
  target_id = aws_organizations_organizational_unit.workloads.id
}
