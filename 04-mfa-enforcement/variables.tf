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
    chapter = "04"
  }
}

variable "console_analyst_user_name" {
  description = "Nome do usuário IAM de exemplo que representa qualquer identidade com login de console por senha (ex.: o mesmo analista de plantão do capítulo 01), membro do grupo que exige MFA."
  type        = string
  default     = "insecurity-inc-console-analyst"
}
