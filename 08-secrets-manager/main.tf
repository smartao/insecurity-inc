data "aws_caller_identity" "current" {}

locals {
  # Vazio (padrão) resolve para a própria identidade que roda o Terraform --
  # ver variables.tf para o porquê. O mesmo padrão dos capítulos 06 e 07.
  checkout_backend_principal_arn = var.checkout_backend_principal_arn != "" ? var.checkout_backend_principal_arn : data.aws_caller_identity.current.arn

  secret_name            = "${var.secret_name_prefix}/db-credentials"
  rotation_function_name = "insecurity-inc-checkout-db-rotation"
}

# ---------------------------------------------------------------------------
# O secret
# ---------------------------------------------------------------------------

# Senha "do dia 1". Efêmera de propósito: existe só durante o plan/apply, nunca
# é gravada no state nem no plan. No capítulo 07 os random_password comuns
# deixaram as senhas em texto claro no terraform.tfstate; aqui, num capítulo
# sobre segredos, não faz sentido repetir o erro.
ephemeral "random_password" "db_password_day1" {
  length = 24
  # Sem aspas, barra, cifrão e backtick -- mesmo critério da Lambda de rotação
  # (EXCLUDE_CHARACTERS em lambda/rotation.py) e do capítulo 07.
  override_special = "!#%*()-_=+"
}

# Sem kms_key_id de propósito: usa a chave gerenciada pela AWS
# "aws/secretsmanager", sem custo de CMK -- mesma decisão do capítulo 07 para o
# Parameter Store. Ver README, seção Correção, ponto 6.
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = local.secret_name
  description = "Credenciais do banco de dados do checkout (dado de laboratório -- não existe banco real neste capítulo). Rotacionado automaticamente."

  # 0 = deleção imediata no destroy. Ver variables.tf para o porquê.
  recovery_window_in_days = var.secret_recovery_window_in_days

  tags = var.tags
}

# Versão inicial do secret -- a "senha do dia 1". Atributo write-only
# (secret_string_wo): o Terraform envia o valor à API mas não o guarda no state,
# e por isso também não tenta "corrigir" o valor quando a rotação o trocar --
# só regrava se secret_string_wo_version mudar. Sem isto, a combinação
# Terraform + rotação briga: o Terraform enxergaria a senha rotacionada como
# drift do valor que ele mesmo gravou.
#
# JSON no mesmo formato dos templates oficiais de rotação de banco da AWS
# (username/password/engine/host/port/dbname), para o dia em que este lab
# ganhar um banco de verdade.
resource "aws_secretsmanager_secret_version" "db_credentials_day1" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string_wo = jsonencode({
    username = var.db_username
    password = ephemeral.random_password.db_password_day1.result
    engine   = "postgres"
    host     = var.db_host
    port     = 5432
    dbname   = "checkout"
  })
  secret_string_wo_version = 1
}

# ---------------------------------------------------------------------------
# A Lambda de rotação
# ---------------------------------------------------------------------------

data "archive_file" "rotation" {
  type        = "zip"
  source_file = "${path.module}/lambda/rotation.py"
  output_path = "${path.module}/rotation.zip"
}

# Log group criado explicitamente: se a Lambda o criasse sozinha no primeiro
# uso, ele nasceria com retenção infinita (custo esquecido que só cresce).
resource "aws_cloudwatch_log_group" "rotation" {
  name              = "/aws/lambda/${local.rotation_function_name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

data "aws_iam_policy_document" "rotation_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rotation" {
  name               = "insecurity-inc-checkout-db-rotation"
  description        = "Execution role da Lambda que rotaciona o secret de credenciais do banco do checkout -- escopada só a este secret."
  assume_role_policy = data.aws_iam_policy_document.rotation_trust.json
  tags               = var.tags
}

# Permissões mínimas da rotation Lambda, no formato da documentação oficial
# ("Lambda rotation function execution role permissions"): as quatro ações de
# secret só neste secret, e GetRandomPassword com Resource "*" (a action não
# tem recurso). Sem statement de KMS: o secret usa a chave gerenciada
# aws/secretsmanager -- só quem usa uma CMK precisa conceder kms:Decrypt ao
# execution role (mesma doc).
data "aws_iam_policy_document" "rotation_permissions" {
  statement {
    sid    = "RotateOnlyThisSecret"
    effect = "Allow"

    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecretVersionStage",
    ]

    resources = [aws_secretsmanager_secret.db_credentials.arn]
  }

  statement {
    # GetRandomPassword não opera sobre nenhum recurso -- Resource "*" é a
    # única forma, e a action não revela nem altera nada de ninguém.
    sid       = "GenerateRandomPasswordRequiresWildcardResource"
    effect    = "Allow"
    actions   = ["secretsmanager:GetRandomPassword"]
    resources = ["*"]
  }

  statement {
    # Só o log group desta função (criado acima), não logs:* em "*". Sem
    # logs:CreateLogGroup: o log group já existe.
    sid       = "WriteOwnLogsOnly"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.rotation.arn}:*"]
  }
}

resource "aws_iam_role_policy" "rotation" {
  name   = "rotate-checkout-db-credentials"
  role   = aws_iam_role.rotation.id
  policy = data.aws_iam_policy_document.rotation_permissions.json
}

resource "aws_lambda_function" "rotation" {
  function_name = local.rotation_function_name
  description   = "Rotaciona o secret ${local.secret_name} (protocolo de 4 etapas; setSecret/testSecret são stubs -- sem banco neste lab)."
  role          = aws_iam_role.rotation.arn

  runtime       = "python3.12"
  handler       = "rotation.lambda_handler"
  architectures = ["arm64"]
  timeout       = 30
  memory_size   = 128

  filename         = data.archive_file.rotation.output_path
  source_code_hash = data.archive_file.rotation.output_base64sha256

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.rotation.name
  }

  tags = var.tags

  # A role só consegue escrever logs depois que a policy inline existe.
  depends_on = [aws_iam_role_policy.rotation]
}

# Permite ao Secrets Manager invocar a função. aws:SourceAccount (via
# source_account) é a recomendação oficial contra "confused deputy" -- só o
# Secrets Manager desta conta consegue disparar a rotação. A documentação
# recomenda NÃO usar também aws:SourceArn quando a função pode servir a mais de
# um secret, porque amarraria a função a um único secret.
resource "aws_lambda_permission" "secrets_manager_invoke" {
  statement_id   = "AllowSecretsManagerInvoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.rotation.function_name
  principal      = "secretsmanager.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
}

# Liga a rotação automática. rotate_immediately (o padrão, explícito aqui para
# ficar visível) dispara uma rotação já no apply: a "senha do dia 1" gravada
# acima é substituída em segundos -- é o ponto do capítulo.
#
# depends_on explícito: o Secrets Manager valida no ato que consegue invocar a
# função (permission), a Lambda precisa das permissões da role (policy) e a
# rotação precisa de uma versão AWSCURRENT para rotacionar (version).
resource "aws_secretsmanager_secret_rotation" "db_credentials" {
  secret_id           = aws_secretsmanager_secret.db_credentials.id
  rotation_lambda_arn = aws_lambda_function.rotation.arn
  rotate_immediately  = true

  rotation_rules {
    automatically_after_days = var.rotation_days
  }

  depends_on = [
    aws_lambda_permission.secrets_manager_invoke,
    aws_iam_role_policy.rotation,
    aws_secretsmanager_secret_version.db_credentials_day1,
  ]
}

# ---------------------------------------------------------------------------
# Quem consome o secret
# ---------------------------------------------------------------------------

# Trust policy simplificada para o principal do Terraform, só para manter o
# laboratório self-contained e testável via "sts assume-role" sem precisar
# subir uma instância EC2. No cenário real, o trust seria para o serviço
# ec2.amazonaws.com -- a aplicação do checkout roda em EC2. Mesma role do
# capítulo 07 (o capítulo 07 precisa estar destruído antes deste apply).
data "aws_iam_policy_document" "checkout_backend_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [local.checkout_backend_principal_arn]
    }
  }
}

resource "aws_iam_role" "checkout_backend" {
  name                 = "insecurity-inc-checkout-backend"
  description          = "Role da aplicação de checkout -- aqui, escopada só à leitura do secret de credenciais do banco."
  assume_role_policy   = data.aws_iam_policy_document.checkout_backend_trust.json
  max_session_duration = 3600
  tags                 = var.tags
}

# Leitura do valor do secret, e só dele. Uma action só (GetSecretValue), um
# Resource só (o ARN completo deste secret, com o sufixo aleatório de 6
# caracteres que o Secrets Manager acrescenta ao nome). Nada de
# "secret:insecurity-inc/*": o ponto do capítulo 07 vale aqui também -- o raio
# de explosão é este secret, não a árvore inteira da conta.
#
# Nenhuma permissão de escrita nem de rotação: quem grava valor novo é a Lambda
# de rotação. Sem statement de KMS: aws/secretsmanager, mesma explicação do
# capítulo 07 (a leitura é autorizada pelo próprio secretsmanager:GetSecretValue).
data "aws_iam_policy_document" "checkout_backend_secret_read" {
  statement {
    sid       = "ReadCheckoutDbCredentials"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.db_credentials.arn]
  }
}

resource "aws_iam_policy" "checkout_backend_secret_read" {
  name        = "insecurity-inc-checkout-backend-secret-read"
  description = "Leitura (não escrita, não rotação) do secret ${local.secret_name} -- não de todos os secrets da conta."
  policy      = data.aws_iam_policy_document.checkout_backend_secret_read.json
  tags        = var.tags
}

resource "aws_iam_role_policy_attachment" "checkout_backend_secret_read" {
  role       = aws_iam_role.checkout_backend.name
  policy_arn = aws_iam_policy.checkout_backend_secret_read.arn
}
