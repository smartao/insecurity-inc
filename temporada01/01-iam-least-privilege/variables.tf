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

variable "instance_type" {
  description = "Tipo de instância EC2 usada para simular a aplicação de checkout. t3.micro é suficiente para o laboratório — a conta usada não tem free tier, então destrua (ou pelo menos pare) as instâncias assim que terminar de testar."
  type        = string
  default     = "t3.micro"
}

variable "checkout_app_instance_names" {
  description = "Nomes (tag Name) das instâncias EC2 que representam a aplicação de checkout — são exatamente as instâncias que a policy least-privilege autoriza o plantão a start/stop/reboot."
  type        = list(string)
  default     = ["insecurity-inc-checkout-app-1", "insecurity-inc-checkout-app-2"]
}

variable "subnet_id" {
  description = "ID da subnet onde as instâncias de exemplo serão criadas. Deixe vazio (\"\") para usar automaticamente a subnet default da VPC default da conta/região."
  type        = string
  default     = ""
}

variable "oncall_user_name" {
  description = "Nome do usuário IAM de exemplo que representa o analista de plantão (on-call), membro do grupo least-privilege."
  type        = string
  default     = "insecurity-inc-oncall-analyst"
}
