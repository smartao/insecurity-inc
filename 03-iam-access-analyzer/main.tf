data "aws_caller_identity" "current" {}

locals {
  # Em produção este seria o Account ID real da consultoria externa. Sem um
  # valor explícito em var.external_account_id, o laboratório aponta para a
  # própria conta -- assim "apply"/"destroy" funcionam sozinhos, sem depender
  # de uma segunda conta AWS que a maioria de quem for reproduzir este
  # capítulo não tem à mão (mesmo racional do subnet_id do capítulo 02).
  external_account_id = var.external_account_id != "" ? var.external_account_id : data.aws_caller_identity.current.account_id
}

# External access analyzer da conta: varre continuamente toda policy baseada
# em recurso (trust policy de IAM Role, bucket policy do S3, key policy do
# KMS, policy de fila do SQS, de secret do Secrets Manager etc.) e gera um
# finding sempre que alguma delas concede acesso a um principal fora da
# "zone of trust" -- aqui, a própria conta (type = ACCOUNT). É o mecanismo de
# detecção que substitui a auditoria manual de trust policy por trust
# policy.
resource "aws_accessanalyzer_analyzer" "external_access" {
  analyzer_name = "insecurity-inc-external-access-analyzer"
  type          = "ACCOUNT"

  tags = var.tags
}

# Trust policy corrigida: Principal escopado à conta específica da
# consultoria (nunca "*") e Condition exigindo sts:ExternalId -- a mitigação
# recomendada pela AWS (SEC03-BP09) para o "confused deputy problem" em
# acesso cross-account concedido a terceiros.
data "aws_iam_policy_document" "external_audit_trust" {
  statement {
    sid     = "AllowExternalAuditorAssumeRoleWithExternalId"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.external_account_id}:root"]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.external_id]
    }
  }
}

resource "aws_iam_role" "external_audit" {
  name        = "insecurity-inc-external-audit-role"
  description = "Role de auditoria para a consultoria de segurança externa -- assume restrito à conta configurada em var.external_account_id + External ID."

  assume_role_policy = data.aws_iam_policy_document.external_audit_trust.json

  tags = var.tags
}

# SecurityAudit é a managed policy que a própria AWS mantém para dar
# visibilidade de configuração de segurança a auditores -- leitura ampla em
# dezenas de serviços, nenhuma permissão de escrita. Diferente do
# AdministratorAccess do capítulo 01, aqui o "acesso amplo" é intencional e
# documentado, mas raso (Describe/List/Get), nunca mutação.
resource "aws_iam_role_policy_attachment" "external_audit_security_audit" {
  role       = aws_iam_role.external_audit.name
  policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
}
