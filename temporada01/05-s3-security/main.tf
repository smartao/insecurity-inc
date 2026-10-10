# Nomes de bucket S3 são únicos globalmente em toda a AWS (não só na conta)
# -- um sufixo aleatório evita colisão com um bucket de qualquer outra conta.
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Bucket de exemplo representando o armazenamento de recibos de pedido do
# checkout (capítulo 01) que precisam ser entregues ao cliente final.
#
# force_destroy = true é uma escolha deliberada de laboratório efêmero: sem
# isso, "terraform destroy" falharia se o objeto de teste da seção "Como
# testar" do README ainda existir no bucket. Nunca use isso em um bucket de
# produção -- apaga todo o conteúdo do bucket silenciosamente no destroy.
resource "aws_s3_bucket" "customer_receipts" {
  bucket        = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"
  force_destroy = true
  tags          = var.tags
}

# Bucket Owner Enforced desativa ACLs por completo neste bucket -- toda
# concessão de acesso passa a depender exclusivamente de bucket policy / IAM
# policy. É o valor padrão para buckets novos desde abril/2023, mas
# declarado aqui de forma explícita porque é o oposto direto do "antes"
# deste capítulo (ACL public-read) -- ver README, seção Cenário. Também é o
# que torna o teste 2 da seção "Como testar" (tentar dar public-read via
# ACL) impossível de propósito.
resource "aws_s3_bucket_ownership_controls" "customer_receipts" {
  bucket = aws_s3_bucket.customer_receipts.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Block Public Access no nível do bucket: nega qualquer tentativa futura de
# tornar o bucket ou seus objetos públicos via bucket policy -- mesmo que
# alguém, mais tarde, anexe por engano uma policy com Principal "*", a AWS
# rejeita a operação antes que ela tenha qualquer efeito (CIS AWS
# Foundations Benchmark v3.0.0, controle 2.1.4; Security Hub S3.8). Sem
# isto, uma bucket policy mal escrita seria suficiente para reabrir o
# problema que este capítulo corrige, independente da ownership control
# acima.
resource "aws_s3_bucket_public_access_block" "customer_receipts" {
  bucket = aws_s3_bucket.customer_receipts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Criptografia em repouso com SSE-S3 (AES-256), sem custo adicional -- a AWS
# já aplica isso por padrão a buckets novos desde 2023, declarado aqui de
# forma explícita para documentar a intenção. Upgrade para SSE-KMS com CMK
# (chave própria, key policy, auditoria de uso) é o assunto completo do
# capítulo 06 -- fora de escopo aqui.
resource "aws_s3_bucket_server_side_encryption_configuration" "customer_receipts" {
  bucket = aws_s3_bucket.customer_receipts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Nega QUALQUER ação no bucket ou em seus objetos quando a requisição não
# usa TLS (aws:SecureTransport = false) -- protege dados em trânsito mesmo
# para quem tem permissão IAM legítima de acessar o bucket (CIS AWS
# Foundations Benchmark v3.0.0, controle 2.1.1; Security Hub S3.5; AWS
# Well-Architected Framework, SEC09-BP02). O Principal "*" aqui, combinado
# com Effect Deny, não abre acesso a ninguém -- é o padrão oficial da AWS
# para este tipo de guarda-rail: nega de todo mundo, inclusive do dono da
# conta, a exceção sendo justamente usar HTTPS.
data "aws_iam_policy_document" "customer_receipts" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.customer_receipts.arn,
      "${aws_s3_bucket.customer_receipts.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "customer_receipts" {
  bucket = aws_s3_bucket.customer_receipts.id
  policy = data.aws_iam_policy_document.customer_receipts.json

  # Cria o Public Access Block antes da bucket policy: evita a corrida de
  # eventual consistency documentada pela própria AWS em que uma policy é
  # avaliada antes do bloqueio de políticas públicas estar de fato ativo.
  depends_on = [aws_s3_bucket_public_access_block.customer_receipts]
}
