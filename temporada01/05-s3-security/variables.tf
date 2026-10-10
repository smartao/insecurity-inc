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
    chapter = "05"
  }
}

variable "bucket_name_prefix" {
  description = "Prefixo do nome do bucket S3 de exemplo. Nome de bucket é único globalmente em toda a AWS, por isso um sufixo aleatório é anexado a este prefixo (ver random_id.bucket_suffix em main.tf)."
  type        = string
  default     = "insecurity-inc-customer-receipts"
}
