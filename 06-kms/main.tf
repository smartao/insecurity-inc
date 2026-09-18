data "aws_caller_identity" "current" {}

locals {
  # Vazio (padrão) resolve para a própria identidade que roda o Terraform --
  # ver variables.tf para o porquê.
  checkout_backend_principal_arn = var.checkout_backend_principal_arn != "" ? var.checkout_backend_principal_arn : data.aws_caller_identity.current.arn
}

# Nomes de bucket S3 são únicos globalmente em toda a AWS (não só na conta)
# -- um sufixo aleatório evita colisão com um bucket de qualquer outra conta.
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Key policy explícita e restrita. Duas decisões deliberadas, em contraste
# direto com o "antes" deste capítulo (ver README, seção Cenário):
#
# 1. NÃO inclui a statement padrão "Enable IAM User Permissions" (Principal
#    = root da conta, Action = kms:*) que a AWS anexaria automaticamente a
#    qualquer CMK criada sem uma "policy" customizada. Essa statement
#    delegaria toda a decisão de acesso para IAM -- e é exatamente isso que
#    faria da key policy um espelho da IAM em vez de um segundo portão
#    independente (Problema, ponto 2). Em troca, os dois principais
#    autorizados (administração e uso) são nomeados explicitamente abaixo.
# 2. O statement de uso é restrito por "kms:ViaService" ao S3 -- nem a
#    própria identidade autorizada consegue chamar kms:Decrypt/Encrypt "a
#    seco", só através de uma operação do S3. Defesa em profundidade extra,
#    no mesmo espírito do DenyInsecureTransport do capítulo 05.
data "aws_iam_policy_document" "customer_receipts_key" {
  statement {
    sid    = "AllowKeyAdministration"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.current.arn]
    }

    actions = [
      "kms:Create*",
      "kms:Describe*",
      "kms:Enable*",
      "kms:List*",
      "kms:Put*",
      "kms:Update*",
      "kms:Revoke*",
      "kms:Disable*",
      "kms:Get*",
      "kms:Delete*",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion",
    ]

    # "Resource" numa key policy sempre se refere só à própria chave a que a
    # policy está anexada -- "*" aqui não é "todas as chaves da conta".
    resources = ["*"]
  }

  statement {
    sid    = "AllowCheckoutBackendKeyUsageViaS3Only"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [local.checkout_backend_principal_arn]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.region}.amazonaws.com"]
    }
  }
}

# CMK simétrica que cifra os recibos de cliente (mesmo dado do capítulo 05),
# agora com key policy, rotação e auditoria própria em vez de SSE-S3.
resource "aws_kms_key" "customer_receipts" {
  description = "CMK do capítulo 06 (insecurity-inc) -- cifra o bucket de recibos de cliente via SSE-KMS."

  # CIS AWS Foundations Benchmark v3.0.0 controle 3.6 / Security Hub KMS.4 --
  # rotação anual automática do material criptográfico por trás da chave.
  enable_key_rotation = true

  deletion_window_in_days = var.key_deletion_window_days
  policy                  = data.aws_iam_policy_document.customer_receipts_key.json
  tags                    = var.tags
}

# Alias amigável -- facilita referenciar a chave sem decorar o key ID, e é o
# nome que aparece nos eventos kms:Decrypt/Encrypt do CloudTrail.
resource "aws_kms_alias" "customer_receipts" {
  name          = "alias/insecurity-inc-customer-receipts"
  target_key_id = aws_kms_key.customer_receipts.key_id
}

# Bucket de exemplo representando o mesmo armazenamento de recibos do
# capítulo 05 -- reconstruído aqui porque cada capítulo deste repositório é
# autocontido (sem módulos compartilhados). Bucket Owner Enforced e Block
# Public Access são reaplicados como linha de base sã; o foco deste
# capítulo é exclusivamente a troca de SSE-S3 (capítulo 05) por SSE-KMS com
# a CMK acima -- a bucket policy DenyInsecureTransport do capítulo 05 não é
# repetida aqui para manter o escopo restrito a KMS.
resource "aws_s3_bucket" "customer_receipts" {
  bucket        = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"
  force_destroy = true
  tags          = var.tags
}

resource "aws_s3_bucket_ownership_controls" "customer_receipts" {
  bucket = aws_s3_bucket.customer_receipts.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "customer_receipts" {
  bucket = aws_s3_bucket.customer_receipts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SSE-KMS com a CMK deste capítulo. bucket_key_enabled reduz em até ~99% o
# número de chamadas do S3 para o KMS (um "bucket key" reaproveita uma data
# key por um tempo limitado em vez de uma chamada a GenerateDataKey por
# objeto) -- relevante numa conta sem free tier, já que cada chamada ao KMS
# além da cota gratuita mensal tem custo.
resource "aws_s3_bucket_server_side_encryption_configuration" "customer_receipts" {
  bucket = aws_s3_bucket.customer_receipts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.customer_receipts.arn
    }

    bucket_key_enabled = true
  }
}
