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

variable "teams" {
  description = "Times de exemplo usados para demonstrar ABAC: cada time ganha uma instância EC2 (tag access-project = time) e um usuário IAM com a mesma tag."
  type        = list(string)
  default     = ["marketing", "engineering"]
}

variable "instance_type" {
  description = "Tipo de instância EC2 usada para simular as aplicações dos times. t3.micro é suficiente para o laboratório — a conta usada não tem free tier, então destrua (ou pelo menos pare) as instâncias assim que terminar de testar."
  type        = string
  default     = "t3.micro"
}

variable "subnet_id" {
  description = "ID da subnet onde as instâncias de exemplo serão criadas. Deixe vazio (\"\") para usar automaticamente a subnet default da VPC default da conta/região."
  type        = string
  default     = ""
}
