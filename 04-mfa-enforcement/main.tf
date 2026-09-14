data "aws_caller_identity" "current" {}

# Grupo representando qualquer identidade com login de console por senha --
# o mesmo tipo de acesso que o analista de plantão do capítulo 01 recebeu.
# Aqui o foco não é o que o grupo pode fazer, é como a sessão foi
# autenticada antes de poder fazer qualquer coisa.
resource "aws_iam_group" "console_users" {
  name = "insecurity-inc-console-users"
}

# Permissão "de negócio" de exemplo -- o describe amplo de sempre (capítulos
# 01/02), só para dar ao grupo algo de fato útil para fazer quando a sessão
# estiver corretamente autenticada. O ponto deste capítulo não é esta
# permissão, é a policy abaixo, que decide quando ela pode ser exercida.
data "aws_iam_policy_document" "console_users_business" {
  statement {
    sid       = "DescribeEC2Instances"
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "console_users_business" {
  name        = "insecurity-inc-console-users-policy"
  description = "Permissão de negócio de exemplo (describe de EC2) para o grupo de usuários de console -- só é exercível de fato quando a sessão está autenticada com MFA (ver insecurity-inc-force-mfa-policy)."
  policy      = data.aws_iam_policy_document.console_users_business.json
  tags        = var.tags
}

# Force MFA: nega TODA ação da conta, exceto uma lista curta e deliberada de
# ações IAM que o próprio usuário precisa para gerenciar sua senha e seu
# dispositivo MFA -- e só nega quando a sessão NÃO está autenticada com MFA
# (aws:MultiFactorAuthPresent). Com MFA presente, esta statement não nega
# nada, e as outras policies do usuário (aqui, a de negócio acima) valem
# normalmente.
#
# Modelo oficial da AWS: "AWS: Allows MFA-authenticated IAM users to manage
# their own credentials on the Security credentials page" (ver README,
# seção Referências) -- reduzido aqui só às ações de senha e MFA, que são o
# que este laboratório precisa para demonstrar o conceito. A versão
# completa da AWS também cobre access keys, certificados de assinatura,
# chaves SSH e Git credentials (CodeCommit); fora do escopo deste capítulo.
data "aws_iam_policy_document" "force_mfa" {
  statement {
    sid       = "AllowViewAccountInfo"
    effect    = "Allow"
    actions   = ["iam:GetAccountPasswordPolicy", "iam:ListVirtualMFADevices"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowManageOwnPasswords"
    effect = "Allow"
    # iam:ChangePassword de propósito NÃO entra na lista de exceções da
    # statement DenyAllExceptListedIfNoMFA abaixo -- ver README ("erro
    # comum" na seção Como testar) sobre o efeito disso num primeiro login.
    actions   = ["iam:ChangePassword", "iam:GetUser"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/$${aws:username}"]
  }

  statement {
    sid       = "AllowManageOwnVirtualMFADevice"
    effect    = "Allow"
    actions   = ["iam:CreateVirtualMFADevice"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:mfa/*"]
  }

  statement {
    sid    = "AllowManageOwnUserMFA"
    effect = "Allow"
    actions = [
      "iam:DeactivateMFADevice",
      "iam:EnableMFADevice",
      "iam:ListMFADevices",
      "iam:ResyncMFADevice",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/$${aws:username}"]
  }

  # O coração da policy: nega tudo que não estiver nesta lista, mas só
  # quando a sessão não tem MFA presente. BoolIfExists trata a ausência da
  # própria chave aws:MultiFactorAuthPresent como "false" -- então
  # credenciais de longa duração usadas sem nenhum contexto de MFA (ex.:
  # uma access key crua, sem passar por sts:GetSessionToken com MFA) também
  # caem nesta negação, não só uma sessão de console sem MFA.
  statement {
    sid    = "DenyAllExceptListedIfNoMFA"
    effect = "Deny"
    not_actions = [
      "iam:CreateVirtualMFADevice",
      "iam:EnableMFADevice",
      "iam:GetUser",
      "iam:GetMFADevice",
      "iam:ListMFADevices",
      "iam:ListVirtualMFADevices",
      "iam:ResyncMFADevice",
      "sts:GetSessionToken",
    ]
    resources = ["*"]

    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["false"]
    }
  }
}

resource "aws_iam_policy" "force_mfa" {
  name        = "insecurity-inc-force-mfa-policy"
  description = "Nega toda ação da conta, exceto autogestão de senha/MFA, enquanto a sessão não estiver autenticada com MFA."
  policy      = data.aws_iam_policy_document.force_mfa.json
  tags        = var.tags
}

# RBAC: as duas policies são anexadas ao GRUPO, nunca diretamente a um
# usuário (CIS AWS Foundations Benchmark v3.0.0, controle 1.15) -- mesmo
# padrão dos capítulos 01/02.
resource "aws_iam_group_policy_attachment" "console_users_business" {
  group      = aws_iam_group.console_users.name
  policy_arn = aws_iam_policy.console_users_business.arn
}

resource "aws_iam_group_policy_attachment" "console_users_force_mfa" {
  group      = aws_iam_group.console_users.name
  policy_arn = aws_iam_policy.force_mfa.arn
}

# Usuário de exemplo representando qualquer identidade com login de console
# por senha (ex.: o mesmo analista de plantão do capítulo 01). Sem login de
# console e sem access key geradas por Terraform, pelo mesmo motivo dos
# capítulos anteriores: credencial de longo prazo não deve viver no state.
resource "aws_iam_user" "console_analyst" {
  name = var.console_analyst_user_name
  tags = var.tags
}

resource "aws_iam_user_group_membership" "console_analyst" {
  user   = aws_iam_user.console_analyst.name
  groups = [aws_iam_group.console_users.name]
}
