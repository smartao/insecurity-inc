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
    chapter = "15"
  }
}

variable "rcp_target_id" {
  description = "Onde a RCP é anexada: um account ID (12 dígitos), uma OU (ou-...) ou o Root (r-...). O padrão é a conta-membro já convidada para a Organization (fora do Terraform -- ver README, Como aplicar). Começar por uma conta de teste e só depois subir para OU/Root é a ordem que a própria AWS recomenda para RCP (ver README, A Correção)."
  type        = string
  default     = "868878695337"

  validation {
    condition     = can(regex("^([0-9]{12}|ou-[0-9a-z]{4,32}-[a-z0-9]{8,32}|r-[0-9a-z]{4,32})$", var.rcp_target_id))
    error_message = "rcp_target_id precisa ser um account ID (12 dígitos), um ID de OU (ou-...) ou o ID do Root (r-...)."
  }
}
