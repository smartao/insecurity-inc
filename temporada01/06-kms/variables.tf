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
    chapter = "06"
  }
}

variable "bucket_name_prefix" {
  description = "Prefixo do nome do bucket S3 de exemplo (mesmo cenário do capítulo 05, reconstruído aqui de forma independente). Nome de bucket é único globalmente em toda a AWS, por isso um sufixo aleatório é anexado a este prefixo (ver random_id.bucket_suffix em main.tf)."
  type        = string
  default     = "insecurity-inc-customer-receipts"
}

variable "key_deletion_window_days" {
  description = "Janela de espera (em dias) antes da CMK ser efetivamente apagada depois que 'terraform destroy' agenda a deleção (ScheduleKeyDeletion). A AWS exige um mínimo de 7 e um máximo de 30 -- durante toda a janela a chave permanece em estado 'Pending deletion', continua sendo cobrada (~US$1/mês, pro-rata) e não pode ser usada para novas operações de criptografia. 7 é o valor mais barato para um laboratório efêmero; nunca use um valor tão baixo em produção sem um processo de revisão -- expirada a janela, a chave e todo dado cifrado exclusivamente por ela são irrecuperáveis (ver Security Hub KMS.3)."
  type        = number
  default     = 7

  validation {
    condition     = var.key_deletion_window_days >= 7 && var.key_deletion_window_days <= 30
    error_message = "A AWS exige um valor entre 7 e 30 dias para deletion_window_in_days."
  }
}

variable "checkout_backend_principal_arn" {
  description = "ARN do principal IAM autorizado a usar a CMK para cifrar/decifrar via S3 -- o 'backend do checkout' do cenário (ver capítulo 01). Vazio (padrão) resolve para a identidade que roda o Terraform, mantendo o capítulo self-contained e testável sem exigir uma role adicional; no cenário real, seria o ARN da role específica do backend."
  type        = string
  default     = ""
}
