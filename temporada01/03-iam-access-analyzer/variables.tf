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
    chapter = "03"
  }
}

variable "external_account_id" {
  description = "Account ID de 12 dígitos da consultoria/terceiro que deve poder assumir a role de auditoria. Deixe vazio (\"\") para o laboratório apontar para a própria conta (self-contained, sem depender de uma segunda conta AWS) -- para o cenário real de acesso cross-account, informe o Account ID real da conta externa."
  type        = string
  default     = ""
}

variable "external_id" {
  description = "Valor de sts:ExternalId exigido na trust policy -- mitigação recomendada pela AWS (SEC03-BP09) contra o confused deputy problem em acesso concedido a terceiros. Não precisa ser tratado como segredo, mas deve ser único por terceiro e difícil de adivinhar; em produção, gere um valor aleatório (ex.: um UUID) por parceiro e nunca reaproveite o mesmo valor entre contas diferentes."
  type        = string
  default     = "insecurity-inc-lab-external-id"
}
