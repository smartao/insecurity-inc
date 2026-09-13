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
    chapter = "02"
  }
}

variable "team_reports_bucket_name" {
  description = "Prefixo do nome do bucket S3 compartilhado entre times, particionado por prefixo/pasta (o account ID é anexado para garantir unicidade global)."
  type        = string
  default     = "insecurity-inc-team-reports-lab"
}

variable "teams" {
  description = "Times de exemplo usados para demonstrar ABAC: cada time vira um prefixo/pasta no bucket e um usuário IAM com a tag access-project correspondente."
  type        = list(string)
  default     = ["marketing", "engineering"]
}
