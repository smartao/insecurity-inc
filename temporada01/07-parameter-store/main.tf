data "aws_caller_identity" "current" {}

locals {
  # Vazio (padrão) resolve para a própria identidade que roda o Terraform --
  # ver variables.tf para o porquê. O mesmo padrão do capítulo 06.
  checkout_backend_principal_arn = var.checkout_backend_principal_arn != "" ? var.checkout_backend_principal_arn : data.aws_caller_identity.current.arn
}

# Valores de laboratório para os dois segredos abaixo -- gerados, nunca
# hardcoded, para não deixar nem um "fake-password-123" no state em texto
# claro dentro deste .tf. override_special evita aspas, barra, cifrão e
# backtick, só para não complicar o quoting dos comandos AWS CLI da seção
# "Como testar" do README.
resource "random_password" "db_password" {
  length           = 24
  override_special = "!#%*()-_=+"
}

resource "random_password" "payment_gateway_api_key" {
  length  = 40
  special = false
}

# Config sensível do backend do checkout: SecureString, cifrado pela chave
# gerenciada pela AWS "alias/aws/ssm" (key_id não é informado de propósito --
# ver README, seção Correção, para o porquê de não reaproveitar a CMK do
# capítulo 06 aqui). Tier Standard (padrão) + throughput padrão: sem custo
# adicional, mantendo este capítulo 🟢.
resource "aws_ssm_parameter" "db_password" {
  name        = "${var.parameter_path_prefix}/db_password"
  description = "Senha do banco de dados do checkout (dado de laboratório, gerado por random_password -- nunca um segredo real)."
  type        = "SecureString"
  value       = random_password.db_password.result
  tags        = var.tags
}

resource "aws_ssm_parameter" "payment_gateway_api_key" {
  name        = "${var.parameter_path_prefix}/payment_gateway_api_key"
  description = "API key do gateway de pagamento usado pelo checkout (dado de laboratório, gerado por random_password -- nunca um segredo real)."
  type        = "SecureString"
  value       = random_password.payment_gateway_api_key.result
  tags        = var.tags
}

# Contraste deliberado: nem tudo é sensível. Uma feature flag não precisa de
# SecureString -- forçar cifra em tudo, indiscriminadamente, não é o oposto
# do Problema deste capítulo, é só um jeito diferente de não pensar sobre o
# dado que está sendo armazenado.
resource "aws_ssm_parameter" "checkout_v2_enabled" {
  name        = "${var.parameter_path_prefix}/feature_checkout_v2_enabled"
  description = "Feature flag do checkout v2 -- não sensível, String é apropriado aqui."
  type        = "String"
  value       = "false"
  tags        = var.tags
}

# Trust policy simplificada para o principal do Terraform, só para manter o
# laboratório self-contained e testável via "sts assume-role" sem precisar
# subir uma instância EC2. No cenário real (capítulo 01), o trust seria para
# o serviço ec2.amazonaws.com -- a aplicação do checkout roda em EC2.
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
  description          = "Role da aplicação de checkout (capítulo 01) -- aqui, escopada só à leitura de config sob var.parameter_path_prefix."
  assume_role_policy   = data.aws_iam_policy_document.checkout_backend_trust.json
  max_session_duration = 3600
  tags                 = var.tags
}

# Policy de leitura escopada ao prefixo do checkout -- resolve o ponto 2 do
# Problema (nomes de parâmetro "flat" que forçavam Resource "*"). Só ações de
# leitura: esta role nunca precisa gravar config.
data "aws_iam_policy_document" "checkout_backend_parameter_read" {
  statement {
    sid    = "ReadCheckoutProdParameters"
    effect = "Allow"

    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]

    # Duas entradas, não uma: ssm:GetParametersByPath avalia o Resource
    # exigido como o PRÓPRIO path, sem "/*" no final -- só o "/*" cobriria
    # GetParameter/GetParameters mas negaria GetParametersByPath (confirmado
    # testando contra a conta real; ver README, seção Como testar). Um único
    # "...prod*" (sem a barra antes do *) também funcionaria para as duas
    # actions, mas combinaria por acidente com um path irmão que começasse
    # com o mesmo prefixo (ex.: /insecurity-inc/checkout/prod-staging) --
    # as duas entradas explícitas abaixo evitam essa colisão.
    resources = [
      "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${var.parameter_path_prefix}",
      "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${var.parameter_path_prefix}/*",
    ]
  }

  statement {
    # ssm:DescribeParameters não suporta permissão a nível de recurso --
    # mesma limitação documentada de ec2:DescribeInstances no capítulo 01
    # (Service Authorization Reference). Resource "*" aqui é uma concessão
    # consciente e documentada, não um descuido: a action em si não revela
    # valor de parâmetro nenhum, só metadados (nome, tipo, data de edição).
    sid       = "DescribeParametersRequiresWildcardResource"
    effect    = "Allow"
    actions   = ["ssm:DescribeParameters"]
    resources = ["*"]
  }

  # Sem statement de kms:Decrypt aqui -- de propósito, não por esquecimento.
  # Os parâmetros SecureString acima usam a chave gerenciada pela AWS
  # (alias/aws/ssm, ver aws_ssm_parameter.db_password), e a documentação
  # oficial é explícita: "you cannot establish access control policies for
  # the default aws/ssm KMS key" -- não há key policy própria para atuar como
  # segundo portão, como na CMK do capítulo 06. Confirmado testando contra a
  # conta real: esta própria role, sem nenhuma permissão de KMS, decifra o
  # db_password normalmente (ver README, seção Como testar, passo 4). O que
  # autoriza a leitura é o ssm:GetParameter -- por isso o escopo por prefixo
  # do "Resource" acima carrega o peso deste capítulo. Um segundo portão
  # independente exigiria uma CMK própria (key_id customizado), com o mesmo
  # custo recorrente (~US$1/mês) do capítulo 06, fora do escopo 🟢 deste
  # capítulo.
}

resource "aws_iam_policy" "checkout_backend_parameter_read" {
  name        = "insecurity-inc-checkout-backend-parameter-read"
  description = "Leitura (não escrita) dos parâmetros de config do checkout sob ${var.parameter_path_prefix} -- não a árvore inteira do Parameter Store da conta."
  policy      = data.aws_iam_policy_document.checkout_backend_parameter_read.json
  tags        = var.tags
}

resource "aws_iam_role_policy_attachment" "checkout_backend_parameter_read" {
  role       = aws_iam_role.checkout_backend.name
  policy_arn = aws_iam_policy.checkout_backend_parameter_read.arn
}
