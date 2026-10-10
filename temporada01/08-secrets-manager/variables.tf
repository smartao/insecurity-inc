variable "region" {
  description = "Região AWS onde os recursos serão criados"
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "Tags padrão aplicadas a todos os recursos deste capítulo"
  type        = map(string)
  default = {
    project = "insecurity-inc"
    env     = "lab"
    chapter = "08"
  }
}

variable "secret_name_prefix" {
  description = "Prefixo hierárquico do nome do secret (ex.: insecurity-inc/checkout/prod/db-credentials). Mesma lição do capítulo 07: um prefixo comum é o que permite escopar a IAM policy a um Resource específico, em vez de precisar de \"*\". Sem \"/\" no início nem no fim, como na convenção da documentação do Secrets Manager."
  type        = string
  default     = "insecurity-inc/checkout/prod"

  validation {
    condition     = can(regex("^[A-Za-z0-9_+=.@-]+(/[A-Za-z0-9_+=.@-]+)*$", var.secret_name_prefix))
    error_message = "secret_name_prefix não deve começar nem terminar com \"/\" e só aceita letras, números e /_+=.@- (ex.: insecurity-inc/checkout/prod)."
  }
}

variable "db_username" {
  description = "Usuário do banco de dados guardado no secret (dado de laboratório: não existe banco real neste capítulo)."
  type        = string
  default     = "checkout_app"
}

variable "db_host" {
  description = "Host do banco de dados guardado no secret. O TLD .invalid (RFC 2606) garante que nunca resolve para nada de verdade -- não existe banco neste laboratório."
  type        = string
  default     = "checkout-db.insecurity-inc.invalid"
}

variable "rotation_days" {
  description = "A cada quantos dias o Secrets Manager rotaciona o secret automaticamente. 30 fica bem dentro do limite de 90 dias que o controle SecretsManager.4 do Security Hub usa por padrão."
  type        = number
  default     = 30

  validation {
    condition     = var.rotation_days >= 1 && var.rotation_days <= 365 && floor(var.rotation_days) == var.rotation_days
    error_message = "rotation_days deve ser um número inteiro entre 1 e 365."
  }
}

variable "secret_recovery_window_in_days" {
  description = "Janela de recuperação do secret ao destruir. 0 = deleção imediata, sem recuperação -- o correto para um laboratório que faz apply/destroy/apply repetido (com janela > 0 o nome do secret fica reservado até a deleção efetiva). Em produção, use 7 a 30: a janela é a rede de segurança contra deleção acidental, e a AWS não cobra por secret marcado para deleção."
  type        = number
  default     = 0

  validation {
    condition     = var.secret_recovery_window_in_days == 0 || (var.secret_recovery_window_in_days >= 7 && var.secret_recovery_window_in_days <= 30)
    error_message = "secret_recovery_window_in_days deve ser 0 (deleção imediata) ou um valor entre 7 e 30."
  }
}

variable "log_retention_days" {
  description = "Retenção, em dias, dos logs da Lambda de rotação no CloudWatch Logs. Criar o log group explicitamente (em vez de deixar a Lambda criá-lo no primeiro uso) evita o padrão da AWS de retenção infinita, que vira custo esquecido."
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days deve ser um dos valores de retenção aceitos pelo CloudWatch Logs (ex.: 1, 3, 5, 7, 14, 30, 60, 90...)."
  }
}

variable "checkout_backend_principal_arn" {
  description = "ARN do principal autorizado a assumir a role do backend do checkout (insecurity-inc-checkout-backend). Vazio (padrão) resolve para a identidade que roda o Terraform, mantendo o capítulo self-contained e testável via 'sts assume-role' sem exigir uma instância EC2 -- no cenário real, o trust seria para o serviço ec2.amazonaws.com, já que a aplicação roda em EC2. Mesmo padrão do capítulo 07."
  type        = string
  default     = ""
}
