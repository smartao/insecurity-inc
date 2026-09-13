data "aws_caller_identity" "current" {}

# Bucket "de negócio" que representa o recurso que a analista de dados
# precisa acessar. Já nasce privado: desde abril/2023 a AWS bloqueia acesso
# público e desabilita ACLs por padrão em todo bucket novo — o hardening
# fino de bucket (Block Public Access explícito, bucket policy, criptografia)
# é o tema do capítulo 05, não deste capítulo.
resource "aws_s3_bucket" "reports" {
  bucket        = "${var.reports_bucket_name}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # bucket de laboratório — permite destroy mesmo com objetos de teste dentro

  tags = var.tags
}

# Policy least-privilege: só as actions que a analista realmente precisa
# (listar, ler e gravar relatórios) e só sobre este bucket específico —
# nunca "Resource": "*". Comparar com o "antes" documentado no README
# (AdministratorAccess anexado direto ao usuário).
data "aws_iam_policy_document" "reports_analyst" {
  statement {
    sid       = "ListReportsBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.reports.arn]
  }

  statement {
    sid    = "ReadWriteReportsObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = ["${aws_s3_bucket.reports.arn}/*"]
  }
}

resource "aws_iam_policy" "reports_analyst" {
  name        = "insecurity-inc-reports-analyst-policy"
  description = "Acesso de leitura/escrita apenas ao bucket de relatórios (least privilege)."
  policy      = data.aws_iam_policy_document.reports_analyst.json
  tags        = var.tags
}

# RBAC: a policy é anexada ao GRUPO, nunca diretamente a um usuário
# (CIS AWS Foundations Benchmark v3.0.0, controle 1.15).
resource "aws_iam_group" "report_analysts" {
  name = "insecurity-inc-report-analysts"
}

resource "aws_iam_group_policy_attachment" "report_analysts" {
  group      = aws_iam_group.report_analysts.name
  policy_arn = aws_iam_policy.reports_analyst.arn
}

# Usuário representando a analista de dados. Sem login de console e sem
# access key geradas por Terraform: credencial de longo prazo não deve viver
# no state. Provisionamento de credencial (ou, melhor, SSO via IAM Identity
# Center) fica fora do escopo deste capítulo — o foco aqui é a estrutura de
# permissões (RBAC), não o ciclo de vida da credencial.
resource "aws_iam_user" "report_analyst" {
  name = var.analyst_user_name
  tags = var.tags
}

resource "aws_iam_user_group_membership" "report_analyst" {
  user   = aws_iam_user.report_analyst.name
  groups = [aws_iam_group.report_analysts.name]
}
