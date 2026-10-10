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
    chapter = "14"
  }
}

variable "ou_name" {
  description = "Nome da OU que recebe as contas-membro (fora da management account) e onde a SCP deste capítulo é anexada."
  type        = string
  default     = "insecurity-inc-workloads"
}

variable "member_account_id" {
  description = "Account ID da conta-membro já convidada para a Organization (fora do Terraform -- ver README, Como aplicar) e movida para dentro da OU deste capítulo."
  type        = string
  default     = "868878695337"
}

variable "member_account_email" {
  description = "E-mail root da conta-membro. Precisa bater exatamente com o valor real (aws organizations list-accounts) -- a API não permite trocar o e-mail de uma conta por aqui, só documenta o valor existente para o import."
  type        = string
  default     = "sergei.martao+aws@gmail.com"
}

variable "member_account_name" {
  description = "Nome da conta-membro, como aparece em aws organizations list-accounts."
  type        = string
  default     = "sergei-aws"
}
