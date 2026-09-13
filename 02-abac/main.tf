data "aws_caller_identity" "current" {}

locals {
  # Nome da tag usada tanto no principal (IAM User/Role) quanto no prefixo dos
  # objetos no bucket. É o "elo" entre identidade e recurso que faz a ABAC
  # funcionar — mantenha o mesmo nome em toda a policy e ao taguear usuários novos.
  access_tag_key = "access-project"
}

# Bucket único, compartilhado entre times. Ao contrário do capítulo 01 (um
# bucket + uma policy por recurso), aqui um único bucket é particionado por
# prefixo/pasta — é a policy ABAC quem decide, em tempo de avaliação, a qual
# prefixo cada identidade tem acesso, com base na própria tag da identidade.
resource "aws_s3_bucket" "team_reports" {
  bucket        = "${var.team_reports_bucket_name}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # bucket de laboratório — permite destroy mesmo com objetos de teste dentro

  tags = var.tags
}

# Marcadores de "pasta" (objetos vazios terminados em "/"), um por time de
# exemplo — só para tornar a estrutura de prefixos visível no console;
# não têm efeito na avaliação da policy.
resource "aws_s3_object" "team_folder" {
  for_each = toset(var.teams)

  bucket  = aws_s3_bucket.team_reports.id
  key     = "${each.value}/"
  content = ""
}

# Policy única e dinâmica: nenhuma statement referencia um time específico.
# O prefixo permitido em ListBucket, e o Resource em GetObject/PutObject, são
# resolvidos em tempo de avaliação a partir da tag aws:PrincipalTag da própria
# identidade que faz a chamada — o mesmo grupo/policy serve qualquer time novo,
# desde que a tag exista e a pasta correspondente exista no bucket.
#
# A condição "Null" é a mitigação recomendada pelo próprio tutorial de ABAC da
# AWS: sem ela, uma identidade SEM a tag access-project teria o valor da
# variável de policy resolvido de forma não documentada, o que poderia liberar
# ou negar acesso de forma imprevisível em vez de simplesmente negar.
data "aws_iam_policy_document" "abac_team_reports" {
  statement {
    sid       = "ListOwnPrefixOnly"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.team_reports.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["$${aws:PrincipalTag/${local.access_tag_key}}/*"]
    }

    condition {
      test     = "Null"
      variable = "aws:PrincipalTag/${local.access_tag_key}"
      values   = ["false"]
    }
  }

  statement {
    sid    = "ReadWriteOwnPrefixOnly"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = ["${aws_s3_bucket.team_reports.arn}/$${aws:PrincipalTag/${local.access_tag_key}}/*"]

    condition {
      test     = "Null"
      variable = "aws:PrincipalTag/${local.access_tag_key}"
      values   = ["false"]
    }
  }
}

resource "aws_iam_policy" "abac_team_reports" {
  name        = "insecurity-inc-abac-team-reports-policy"
  description = "Acesso dinâmico ao bucket compartilhado: cada identidade só enxerga o prefixo (pasta) que corresponde à sua própria tag access-project (ABAC)."
  policy      = data.aws_iam_policy_document.abac_team_reports.json
  tags        = var.tags
}

# RBAC continua presente por baixo da ABAC: a policy é anexada ao GRUPO, nunca
# diretamente a um usuário (CIS AWS Foundations Benchmark v3.0.0, controle
# 1.15) — ABAC substitui a explosão de POLICIES por time, não a estrutura de
# grupos.
resource "aws_iam_group" "abac_analysts" {
  name = "insecurity-inc-abac-analysts"
}

resource "aws_iam_group_policy_attachment" "abac_analysts" {
  group      = aws_iam_group.abac_analysts.name
  policy_arn = aws_iam_policy.abac_team_reports.arn
}

# Um usuário de exemplo por time, todos no MESMO grupo, com a MESMA policy —
# o que muda de um time para o outro é só o valor da tag access-project.
# Sem login de console e sem access key geradas por Terraform (mesmo
# racional do capítulo 01: credencial de longo prazo não deve viver no state).
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
