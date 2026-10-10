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
    chapter = "10"
  }
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC do laboratório. Uma VPC dedicada, em vez da VPC padrão da conta, para o capítulo poder ser destruído sem deixar rastro. A subnet é o primeiro /24 (índice 1) desse bloco -- por isso o prefixo da VPC vai de /16 a /20 (com /20 a subnet ainda cabe, como /28, o menor tamanho que a AWS aceita)."
  type        = string
  default     = "10.10.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && can(regex("/(1[6-9]|20)$", var.vpc_cidr))
    error_message = "vpc_cidr deve ser um CIDR IPv4 válido com prefixo entre /16 e /20 (ex.: 10.10.0.0/16)."
  }
}

variable "traffic_type" {
  description = "Tipo de tráfego capturado pelo flow log: ALL, ACCEPT ou REJECT. O Security Hub (EC2.6) e a regra do Config (vpc-flow-logs-enabled) já ficam satisfeitos com REJECT -- é o mínimo de conformidade. O padrão aqui é ALL, de propósito: sem os ACCEPT também não dá para responder se algo que não devia passar, passou mesmo assim (ver README, Problema)."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ALL", "ACCEPT", "REJECT"], var.traffic_type)
    error_message = "traffic_type deve ser ALL, ACCEPT ou REJECT."
  }
}

variable "max_aggregation_interval" {
  description = "Janela de agregação dos registros, em segundos: 60 (1 minuto) ou 600 (10 minutos, o padrão da AWS). 60 gera mais registros (e um pouco mais de custo de ingestão) em troca de os dados aparecerem mais rápido -- vale a pena num laboratório que existe só durante o teste. Em instâncias Nitro a AWS já usa no máximo 1 minuto de qualquer forma, segundo a documentação."
  type        = number
  default     = 60

  validation {
    condition     = contains([60, 600], var.max_aggregation_interval)
    error_message = "max_aggregation_interval deve ser 60 ou 600 (os dois únicos valores aceitos pela API)."
  }
}

variable "log_retention_days" {
  description = "Retenção do CloudWatch Log Group, em dias. Curta de propósito (padrão: 1 dia): este laboratório é destruído ao final do teste, e o log group vai junto -- a retenção só limita o estrago de alguém esquecer o 'terraform destroy'. Precisa ser um dos valores que a API do CloudWatch Logs aceita (não é um número livre)."
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653, 0], var.log_retention_days)
    error_message = "log_retention_days deve ser um dos valores aceitos pelo CloudWatch Logs (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653 ou 0 para nunca expirar)."
  }
}
