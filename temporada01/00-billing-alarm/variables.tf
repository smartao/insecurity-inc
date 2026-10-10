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
    chapter = "00"
  }
}

variable "alert_email" {
  description = "E-mail que recebe as notificações do CloudWatch Billing Alarm (via SNS) e do AWS Budget."
  type        = string
  default     = "sergei.martao@gmail.com"
}

variable "monthly_budget_usd" {
  description = "Limite mensal (USD) do AWS Budget. Também usado como referência para o alarme do CloudWatch."
  type        = number
  default     = 10
}

variable "billing_alarm_threshold_usd" {
  description = "Limite (USD) de gastos estimados no mês que dispara o CloudWatch Billing Alarm (métrica AWS/Billing EstimatedCharges)."
  type        = number
  default     = 10
}
