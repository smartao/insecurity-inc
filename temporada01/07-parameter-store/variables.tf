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
    chapter = "07"
  }
}

variable "parameter_path_prefix" {
  description = "Prefixo hierárquico sob o qual todos os parâmetros de config do checkout são armazenados (ex.: /insecurity-inc/checkout/prod/db_password). É esse prefixo comum que permite escopar a IAM policy de leitura a um Resource específico em vez de precisar de \"*\" -- ver main.tf e README (seção Problema, ponto 2)."
  type        = string
  default     = "/insecurity-inc/checkout/prod"

  validation {
    condition     = can(regex("^/", var.parameter_path_prefix)) && !can(regex("/$", var.parameter_path_prefix))
    error_message = "parameter_path_prefix deve começar com \"/\" e não terminar com \"/\" (ex.: /insecurity-inc/checkout/prod)."
  }
}

variable "checkout_backend_principal_arn" {
  description = "ARN do principal autorizado a assumir a role do backend do checkout (insecurity-inc-checkout-backend). Vazio (padrão) resolve para a identidade que roda o Terraform, mantendo o capítulo self-contained e testável via 'sts assume-role' sem exigir uma instância EC2 -- no cenário real (capítulo 01), o trust seria para o serviço ec2.amazonaws.com, já que a aplicação roda em EC2."
  type        = string
  default     = ""
}
