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
    chapter = "09"
  }
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC do laboratório. Uma VPC dedicada, em vez da VPC padrão da conta, para o capítulo poder ser destruído sem deixar rastro e sem mexer no default security group de um recurso que já existia antes dele. A subnet é o primeiro /24 (índice 1) desse bloco -- por isso o prefixo da VPC vai de /16 a /20 (com /20 a subnet ainda cabe, como /28, o menor tamanho que a AWS aceita)."
  type        = string
  default     = "10.9.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && can(regex("/(1[6-9]|20)$", var.vpc_cidr))
    error_message = "vpc_cidr deve ser um CIDR IPv4 válido com prefixo entre /16 e /20 (ex.: 10.9.0.0/16)."
  }
}

variable "app_port" {
  description = "Porta TCP em que a camada app (backend do checkout) escuta. É a única porta que a camada web pode alcançar na camada app."
  type        = number
  default     = 8080

  validation {
    condition     = var.app_port >= 1 && var.app_port <= 65535 && floor(var.app_port) == var.app_port
    error_message = "app_port deve ser um número inteiro entre 1 e 65535."
  }
}

variable "db_port" {
  description = "Porta TCP do banco de dados. 5432 (PostgreSQL) é a mesma porta do secret de credenciais do capítulo 08. É a única porta que a camada app pode alcançar na camada de banco."
  type        = number
  default     = 5432

  validation {
    condition     = var.db_port >= 1 && var.db_port <= 65535 && floor(var.db_port) == var.db_port
    error_message = "db_port deve ser um número inteiro entre 1 e 65535."
  }
}
