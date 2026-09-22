data "aws_caller_identity" "current" {}

# O nome do trail e o ARN dele são decididos aqui, em vez de deixar o
# Terraform inferir o ARN depois de criado -- a bucket policy (abaixo) e a
# policy do papel de CloudWatch Logs (mais abaixo) PRECISAM do ARN do trail
# na condição aws:SourceArn, mas a AWS só aceita criar um trail (CreateTrail)
# depois que essas permissões já existem: uma referência direta a
# aws_cloudtrail.main.arn nelas criaria uma dependência circular. Como o ARN
# de um trail é 100% previsível a partir do nome (que este código escolhe,
# não a AWS), montá-lo à mão em vez de referenciar o recurso quebra o ciclo --
# mesmo raciocínio do ARN com curinga que o capítulo 10 usa para o papel de
# flow logs, só que aqui dá pra ser exato, sem curinga nenhum.
locals {
  trail_name = "insecurity-inc-trail"
  trail_arn  = "arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.current.account_id}:trail/${local.trail_name}"
}

# Nomes de bucket S3 são únicos globalmente em toda a AWS -- um sufixo
# aleatório evita colisão com um bucket de qualquer outra conta. Os dois
# buckets abaixo (logs do trail e access log desse bucket) compartilham o
# mesmo sufixo: os nomes completos continuam únicos porque os prefixos são
# diferentes, e um único random_id é mais simples de acompanhar que dois.
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# ---------------------------------------------------------------------------
# Bucket de destino do trail -- para onde o CloudTrail entrega os arquivos de
# log (e os arquivos de digest da validação de integridade, ponto 2 da
# Correção)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket        = "insecurity-inc-cloudtrail-logs-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = merge(var.tags, { Name = "insecurity-inc-cloudtrail-logs" })
}

resource "aws_s3_bucket_ownership_controls" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SSE-S3 (AES256), não SSE-KMS: Security Hub CloudTrail.2 / CIS 3.5 pede uma
# CMK, mas uma CMK cobra ~US$1/mês (capítulo 06) -- custo incompatível com o
# 🟢 deste capítulo no roadmap. Ver README, Dívidas em aberto.
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Security Hub CloudTrail.7 / CIS 3.4 (v5.0.0/v3.0.0; 3.6 em v1.4.0; 2.6 em
# v1.2.0): o bucket que guarda os logs do CloudTrail precisa, ele mesmo, de
# access logging -- para onde vai é o segundo bucket, abaixo.
resource "aws_s3_bucket_logging" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "cloudtrail-bucket-access-logs/"
}

# Bucket policy oficial da AWS para entrega de trail (GetBucketAcl +
# PutObject, restritos ao prefixo AWSLogs/<account-id>/), com o acréscimo de
# aws:SourceArn nas duas statements -- a própria documentação da AWS chama
# isso de "security best practice" e recomenda adicionar à parte; o exemplo
# "básico" que a AWS mostra primeiro não inclui. Mesmo padrão de "mais
# restrito que a referência" dos capítulos 06 e 10.
data "aws_iam_policy_document" "cloudtrail_logs_bucket" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail_logs.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  policy = data.aws_iam_policy_document.cloudtrail_logs_bucket.json
}

# ---------------------------------------------------------------------------
# Bucket de access logging do bucket acima -- Security Hub CloudTrail.7
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "access_logs" {
  bucket        = "insecurity-inc-cloudtrail-logs-access-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = merge(var.tags, { Name = "insecurity-inc-cloudtrail-logs-access" })
}

resource "aws_s3_bucket_ownership_controls" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Com Bucket Owner Enforced (ACLs desligadas), o grupo "S3 Log Delivery" da
# forma antiga (grant de ACL) não é uma opção -- a própria documentação da
# AWS diz para usar bucket policy em vez disso, concedendo a ação diretamente
# ao principal de serviço "logging.s3.amazonaws.com". aws:SourceArn +
# aws:SourceAccount travam a entrega ao tráfego que vem realmente do bucket
# de logs do trail, não de qualquer bucket desta conta.
data "aws_iam_policy_document" "access_logs_bucket" {
  statement {
    sid    = "S3ServerAccessLogsPolicy"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.access_logs.arn}/cloudtrail-bucket-access-logs/*"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.cloudtrail_logs.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  policy = data.aws_iam_policy_document.access_logs_bucket.json
}

# ---------------------------------------------------------------------------
# Para onde o trail também envia uma cópia em tempo real: um log group
# dedicado do CloudWatch Logs (Security Hub CloudTrail.5 / CIS 3.4 em
# v1.4.0, 2.4 em v1.2.0 -- a CIS removeu este requisito em v3.0.0/v5.0.0, mas
# o controle do Security Hub continua existindo, e a necessidade real por
# trás dele -- dar para alarme/EventBridge algo para reagir em tempo real --
# não desapareceu por causa disso)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/insecurity-inc/cloudtrail"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, { Name = "insecurity-inc-cloudtrail" })
}

# Papel que o CloudTrail assume para publicar no log group -- e só nele.
# Condição aws:SourceArn: proteção contra confused deputy que a própria
# documentação da AWS recomenda para a bucket policy, mas cujo exemplo de
# trust policy do papel de CloudWatch Logs (citado no README) não inclui.
# Mesmo acréscimo que o capítulo 10 faz para o papel de flow logs.
resource "aws_iam_role" "cloudtrail_cloudwatch_logs" {
  name = "insecurity-inc-cloudtrail-cloudwatch-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceArn" = local.trail_arn }
      }
    }]
  })

  tags = merge(var.tags, { Name = "insecurity-inc-cloudtrail-cloudwatch-logs" })
}

# Nomeação de log stream que o CloudTrail usa, documentada oficialmente:
# "{account-id}_CloudTrail_{home-region-do-trail}", com um sufixo numérico
# ("_2", "_3"...) quando o volume de eventos exige mais de um stream. O
# curinga no final cobre esse caso -- sem ele, um pico de eventos poderia
# gerar um stream sem permissão, e a entrega falharia em silêncio para esse
# stream específico (mesmo tipo de risco documentado no capítulo 10).
resource "aws_iam_role_policy" "cloudtrail_cloudwatch_logs" {
  name = "insecurity-inc-cloudtrail-cloudwatch-logs-publish"
  role = aws_iam_role.cloudtrail_cloudwatch_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
      ]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:log-stream:${data.aws_caller_identity.current.account_id}_CloudTrail_${var.region}*"
    }]
  })
}

# ---------------------------------------------------------------------------
# O trail em si -- multi-região, validação de integridade, todos os eventos
# de gerenciamento (leitura e escrita), com cópia em tempo real no
# CloudWatch Logs
# ---------------------------------------------------------------------------

resource "aws_cloudtrail" "main" {
  name = local.trail_name

  s3_bucket_name = aws_s3_bucket.cloudtrail_logs.id

  # Security Hub CloudTrail.1 / CIS 3.1: um trail multi-região é o único jeito
  # de cobrir todas as regiões habilitadas da conta com uma única
  # configuração -- inclusive detectar atividade numa região que a
  # Insecurity Inc. nunca usou de propósito (ver README, Cenário). Exige
  # include_global_service_events = true (a API rejeita multi-região sem
  # isso).
  is_multi_region_trail         = true
  include_global_service_events = true

  # Security Hub CloudTrail.4 / CIS 3.2: cria os arquivos de digest
  # assinados no bucket, que provam se um arquivo de log foi alterado,
  # apagado ou preservado intacto depois da entrega.
  enable_log_file_validation = true

  # Cópia em tempo real no CloudWatch Logs -- Security Hub CloudTrail.5.
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch_logs.arn

  # Eventos de gerenciamento, leitura e escrita -- o mínimo que o
  # CloudTrail.1 exige, e também o que já vem por padrão sem este bloco.
  # Declarado explicitamente para deixar claro, ao lado do Problema, que
  # eventos de DADOS (leitura/escrita de objeto em buckets S3 específicos --
  # Security Hub S3.22/S3.23) continuam de fora: ver README, Dívidas em
  # aberto.
  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = merge(var.tags, { Name = "insecurity-inc-trail" })

  # Ordem explícita: a API CreateTrail valida a bucket policy e a permissão
  # do papel de CloudWatch Logs NA HORA da criação -- sem essa dependência,
  # o Terraform poderia tentar criar o trail antes de qualquer uma das duas
  # existir (a ordem natural do grafo já cobriria a bucket policy, por causa
  # da referência a aws_s3_bucket.cloudtrail_logs.id acima, mas não cobre a
  # policy do papel de CloudWatch Logs, que só é referenciada pelo ARN do
  # papel, não pela policy em si).
  depends_on = [
    aws_s3_bucket_policy.cloudtrail_logs,
    aws_iam_role_policy.cloudtrail_cloudwatch_logs,
  ]
}
