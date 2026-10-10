data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Bucket de destino do delivery channel -- snapshots periódicos e histórico
# de configuração que o AWS Config entrega. Mesma linha de base dos buckets
# de log dos capítulos 05/06/10/11: Bucket Owner Enforced, Block Public
# Access nas quatro opções, SSE-S3. Sem par de access logging -- nenhum
# controle deste capítulo (ao contrário do CloudTrail.7 no capítulo 11) exige
# isso, e o capítulo 05 já estabeleceu que access logging só entra quando um
# controle nomeado pede.
# ---------------------------------------------------------------------------

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "config" {
  bucket        = "insecurity-inc-config-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = merge(var.tags, { Name = "insecurity-inc-config" })
}

resource "aws_s3_bucket_ownership_controls" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket = aws_s3_bucket.config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bucket policy de referência oficial da AWS para o delivery channel do
# Config (PermissionsCheck + ExistenceCheck + Delivery), com o acréscimo de
# aws:SourceArn -- mesmo padrão "mais restrito que a referência" dos
# capítulos 06/10/11; a documentação mostra só aws:SourceAccount. Vale a pena
# mesmo usando o papel vinculado a serviço abaixo: esse papel NÃO tem
# permissão de escrever no S3 -- quem entrega os arquivos é o principal de
# serviço config.amazonaws.com, e é ele que precisa da permissão aqui (ver
# README, Correção, ponto 3 -- pegadinha resolvida, não vivida).
data "aws_iam_policy_document" "config_bucket" {
  statement {
    sid    = "AWSConfigBucketPermissionsCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.config.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:config:${var.region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }

  statement {
    sid    = "AWSConfigBucketExistenceCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.config.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:config:${var.region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }

  statement {
    sid    = "AWSConfigBucketDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.config.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:config:${var.region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }
}

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id
  policy = data.aws_iam_policy_document.config_bucket.json
}

# ---------------------------------------------------------------------------
# Papel vinculado a serviço (service-linked role) -- exatamente o que o
# Security Hub audita no controle Config.1 ("... and uses the service-linked
# role AWSServiceRoleForConfig"). Um papel IAM próprio com a managed policy
# AWS_ConfigRole (o padrão dos capítulos 10/11 para flow logs e CloudTrail)
# reprovaria esse controle por padrão -- ver README, Correção e Dívidas em
# aberto.
# ---------------------------------------------------------------------------

resource "aws_iam_service_linked_role" "config" {
  aws_service_name = "config.amazonaws.com"
}

# ---------------------------------------------------------------------------
# O recorder -- gravação contínua (mais barata que periódica: US$0,003 vs
# US$0,012 por item, ver README, Nota de custo), mas só dos três tipos de
# recurso que as dez regras deste capítulo realmente precisam (ver README,
# Correção, ponto 1) -- não ALL_SUPPORTED_RESOURCE_TYPES, que é o que o
# Security Hub Config.1 exige e que este capítulo decide não fazer, de
# propósito, por custo (Dívidas em aberto).
# ---------------------------------------------------------------------------

resource "aws_config_configuration_recorder" "main" {
  name     = "insecurity-inc-recorder"
  role_arn = aws_iam_service_linked_role.config.arn

  recording_group {
    all_supported = false

    # AWS::IAM::* é o único grupo de tipos "global" nesta lista -- não é o
    # caso aqui (os três tipos abaixo são todos regionais), então a
    # pegadinha de "gravar recurso global em mais de uma região" (ver
    # README, Dívidas em aberto) não se aplica a este capítulo hoje, só a
    # uma extensão futura dele.
    resource_types = [
      "AWS::EC2::SecurityGroup",
      "AWS::EC2::VPC",
      "AWS::SecretsManager::Secret",
    ]

    recording_strategy {
      use_only = "INCLUSION_BY_RESOURCE_TYPES"
    }
  }

  recording_mode {
    recording_frequency = "CONTINUOUS"
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "insecurity-inc-channel"
  s3_bucket_name = aws_s3_bucket.config.id

  # Delivery Channel exige que o Recorder já exista, e a entrega em si exige
  # a bucket policy já aplicada -- sem essas duas dependências explícitas, o
  # grafo natural do Terraform (que só enxerga a referência a
  # aws_s3_bucket.config.id) não garante a ordem certa.
  depends_on = [
    aws_config_configuration_recorder.main,
    aws_s3_bucket_policy.config,
  ]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  # Iniciar a gravação exige que o Delivery Channel já exista.
  depends_on = [aws_config_delivery_channel.main]
}

# ---------------------------------------------------------------------------
# As dez regras gerenciadas -- cada uma fecha uma promessa específica feita
# em prosa por um capítulo anterior (citações exatas no README, Correção,
# ponto 4). Todas dependem do recorder já estar gravando: uma regra criada
# antes disso não tem erro, mas também não tem nada para avaliar.
# ---------------------------------------------------------------------------

# INCOMING_SSH_DISABLED -- NON_COMPLIANT se algum security group libera a
# porta 22 para 0.0.0.0/0 ou ::/0. Citada, sem estar ligada, no capítulo 09
# (Problema, ponto 6).
resource "aws_config_config_rule" "restricted_ssh" {
  name        = "insecurity-inc-restricted-ssh"
  description = "SSH (22) não pode estar aberto para 0.0.0.0/0 ou ::/0 em nenhum security group."

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }

  maximum_execution_frequency = "TwentyFour_Hours"

  depends_on = [aws_config_configuration_recorder_status.main]
}

# RESTRICTED_INCOMING_TRAFFIC -- NON_COMPLIANT se alguma das portas TCP
# listadas em blockedPorts estiver aberta para 0.0.0.0/0 ou ::/0.
# Parametrizada com as duas portas do Cenário do capítulo 09 (22 do SSH, 5432
# do Postgres) -- os padrões da AWS (20/21/3389/3306/4333) não cobrem nenhuma
# das duas.
resource "aws_config_config_rule" "restricted_common_ports" {
  name        = "insecurity-inc-restricted-common-ports"
  description = "Portas TCP de blockedPorts (22 e 5432) não podem estar abertas para 0.0.0.0/0 ou ::/0."

  source {
    owner             = "AWS"
    source_identifier = "RESTRICTED_INCOMING_TRAFFIC"
  }

  input_parameters            = jsonencode({ blockedPorts = "22,5432" })
  maximum_execution_frequency = "TwentyFour_Hours"

  depends_on = [aws_config_configuration_recorder_status.main]
}

# VPC_DEFAULT_SECURITY_GROUP_CLOSED -- NON_COMPLIANT se o default security
# group de qualquer VPC (inclusive a padrão da conta) tiver alguma regra de
# entrada ou saída. Continua vigiando, de forma contínua, o que o capítulo 09
# zerou uma vez via Terraform (aws_default_security_group.lab).
resource "aws_config_config_rule" "vpc_default_security_group_closed" {
  name        = "insecurity-inc-vpc-default-security-group-closed"
  description = "O default security group de qualquer VPC não pode ter regra de entrada nem de saída."

  source {
    owner             = "AWS"
    source_identifier = "VPC_DEFAULT_SECURITY_GROUP_CLOSED"
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}

# VPC_SG_OPEN_ONLY_TO_AUTHORIZED_PORTS -- para security group aberto a
# 0.0.0.0/0 ou ::/0, só é COMPLIANT se as únicas portas TCP liberadas
# estiverem em authorizedTcpPorts (80/443 aqui); sem essa exposição, a regra
# dá NOT_APPLICABLE, não COMPLIANT.
resource "aws_config_config_rule" "vpc_sg_authorized_ports" {
  name        = "insecurity-inc-vpc-sg-open-only-to-authorized-ports"
  description = "Security group aberto para 0.0.0.0/0 ou ::/0 só pode liberar as portas TCP de authorizedTcpPorts (80/443)."

  source {
    owner             = "AWS"
    source_identifier = "VPC_SG_OPEN_ONLY_TO_AUTHORIZED_PORTS"
  }

  input_parameters            = jsonencode({ authorizedTcpPorts = "80,443" })
  maximum_execution_frequency = "TwentyFour_Hours"

  depends_on = [aws_config_configuration_recorder_status.main]
}

# VPC_FLOW_LOGS_ENABLED -- NON_COMPLIANT se alguma VPC não tiver flow logs
# habilitados. Citada, sem estar ligada, no capítulo 10 (Referências) -- é a
# regra por trás do Security Hub EC2.6.
resource "aws_config_config_rule" "vpc_flow_logs_enabled" {
  name        = "insecurity-inc-vpc-flow-logs-enabled"
  description = "Toda VPC precisa ter flow logs habilitados."

  source {
    owner             = "AWS"
    source_identifier = "VPC_FLOW_LOGS_ENABLED"
  }

  maximum_execution_frequency = "TwentyFour_Hours"

  depends_on = [aws_config_configuration_recorder_status.main]
}

# SECRETSMANAGER_ROTATION_ENABLED_CHECK -- NON_COMPLIANT se o secret não
# tiver rotação agendada, ou rotacionar com frequência maior que
# maximumAllowedRotationFrequency. Limite de 90 dias alinhado ao Security Hub
# SecretsManager.4, citado pelo próprio capítulo 08.
resource "aws_config_config_rule" "secretsmanager_rotation_enabled" {
  name        = "insecurity-inc-secretsmanager-rotation-enabled-check"
  description = "Secret precisa ter rotação agendada, com frequência de até maximumAllowedRotationFrequency dias."

  source {
    owner             = "AWS"
    source_identifier = "SECRETSMANAGER_ROTATION_ENABLED_CHECK"
  }

  # A API exige o valor como STRING dentro do JSON, apesar de a documentação
  # da regra dizer "Type: int" -- jsonencode({ ... = 90 }) (número JSON) falha
  # com "Blank spaces are not acceptable for input parameter" (mensagem
  # enganosa; o problema real é o tipo, não espaço em branco). Confirmado
  # nesta conta via `aws configservice put-config-rule` direto.
  input_parameters = jsonencode({ maximumAllowedRotationFrequency = "90" })

  depends_on = [aws_config_configuration_recorder_status.main]
}

# SECRETSMANAGER_SCHEDULED_ROTATION_SUCCESS_CHECK -- NON_COMPLIANT se a data
# de rotação calculada pelo Secrets Manager passar sem rotação bem-sucedida.
# NOT_APPLICABLE para secret sem rotação agendada.
resource "aws_config_config_rule" "secretsmanager_scheduled_rotation_success" {
  name        = "insecurity-inc-secretsmanager-scheduled-rotation-success-check"
  description = "A rotação agendada do secret precisa acontecer na data calculada pelo Secrets Manager."

  source {
    owner             = "AWS"
    source_identifier = "SECRETSMANAGER_SCHEDULED_ROTATION_SUCCESS_CHECK"
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}

# SECRETSMANAGER_SECRET_PERIODIC_ROTATION -- NON_COMPLIANT se o secret não
# rotacionou nos últimos maxDaysSinceRotation dias (padrão da própria regra,
# 90, mantido).
resource "aws_config_config_rule" "secretsmanager_periodic_rotation" {
  name        = "insecurity-inc-secretsmanager-secret-periodic-rotation"
  description = "Secret precisa ter rotacionado nos últimos maxDaysSinceRotation dias."

  source {
    owner             = "AWS"
    source_identifier = "SECRETSMANAGER_SECRET_PERIODIC_ROTATION"
  }

  maximum_execution_frequency = "TwentyFour_Hours"

  depends_on = [aws_config_configuration_recorder_status.main]
}

# SECRETSMANAGER_SECRET_UNUSED -- NON_COMPLIANT se o secret não foi lido
# (GetSecretValue) nos últimos unusedForDays dias (padrão da própria regra,
# 90, mantido). LastAccessedDate vem do próprio Secrets Manager
# (DescribeSecret), não do CloudTrail -- ver README, Como testar, para o
# comportamento observado com um secret recém-criado, que nunca foi lido.
resource "aws_config_config_rule" "secretsmanager_secret_unused" {
  name        = "insecurity-inc-secretsmanager-secret-unused"
  description = "Secret precisa ter sido lido (GetSecretValue) nos últimos unusedForDays dias."

  source {
    owner             = "AWS"
    source_identifier = "SECRETSMANAGER_SECRET_UNUSED"
  }

  maximum_execution_frequency = "TwentyFour_Hours"

  depends_on = [aws_config_configuration_recorder_status.main]
}

# SECRETSMANAGER_USING_CMK -- COMPLIANT só com CMK do KMS; a chave gerenciada
# pela AWS (aws/secretsmanager) é NON_COMPLIANT. O secret do capítulo 08 usa
# a chave da AWS de propósito (ver README daquele capítulo) -- ficar
# NON_COMPLIANT aqui é o resultado esperado, não um bug: ver README, Dívidas
# em aberto.
resource "aws_config_config_rule" "secretsmanager_using_cmk" {
  name        = "insecurity-inc-secretsmanager-using-cmk"
  description = "Secret precisa estar criptografado com uma CMK do KMS, não com a chave gerenciada pela AWS."

  source {
    owner             = "AWS"
    source_identifier = "SECRETSMANAGER_USING_CMK"
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}
