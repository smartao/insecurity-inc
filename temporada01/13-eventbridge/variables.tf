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
    chapter = "13"
  }
}

variable "alert_email" {
  description = "E-mail que recebe os alertas de NON_COMPLIANT do AWS Config (via SNS)."
  type        = string
  default     = "sergei.martao@gmail.com"
}
