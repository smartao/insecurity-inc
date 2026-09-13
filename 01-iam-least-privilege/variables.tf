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
    chapter = "01"
  }
}

variable "reports_bucket_name" {
  description = "Prefixo do nome do bucket S3 que representa o recurso alvo da policy least-privilege (o account ID é anexado para garantir unicidade global)."
  type        = string
  default     = "insecurity-inc-reports-lab"
}

variable "analyst_user_name" {
  description = "Nome do usuário IAM de exemplo que representa a analista de dados, membro do grupo least-privilege."
  type        = string
  default     = "insecurity-inc-report-analyst"
}
