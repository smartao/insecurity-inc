variable "region" {
  description = "Região AWS onde os recursos serão criados. Também a região \"home\" do trail multi-região -- é para onde todos os eventos de todas as regiões habilitadas convergem (ver README, Correção)."
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "Tags padrão aplicadas a todos os recursos deste capítulo"
  type        = map(string)
  default = {
    project = "insecurity-inc"
    env     = "lab"
    chapter = "11"
  }
}

variable "log_retention_days" {
  description = "Retenção do CloudWatch Log Group que recebe cópia dos eventos do trail, em dias. Curta de propósito (padrão: 1 dia): este laboratório é destruído ao final do teste, e a cópia no S3 (a fonte de verdade do CloudTrail, sem prazo de expiração automático) vai junto só quando o bucket é esvaziado no destroy. Precisa ser um dos valores que a API do CloudWatch Logs aceita (não é um número livre) -- mesma lista do capítulo 10."
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653, 0], var.log_retention_days)
    error_message = "log_retention_days deve ser um dos valores aceitos pelo CloudWatch Logs (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653 ou 0 para nunca expirar)."
  }
}
