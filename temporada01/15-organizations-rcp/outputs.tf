output "organization_id" {
  description = "ID da Organization (pré-existente -- este capítulo só lê). É o valor usado em aws:PrincipalOrgID na RCP."
  value       = data.aws_organizations_organization.this.id
}

output "root_id" {
  description = "ID do Root da Organization."
  value       = data.aws_organizations_organization.this.roots[0].id
}

output "rcp_policy_id" {
  description = "ID da RCP de perímetro de dados."
  value       = aws_organizations_policy.data_perimeter.id
}

output "rcp_policy_arn" {
  description = "ARN da RCP -- é o que aparece nas mensagens de AccessDenied 'with an explicit deny in a resource control policy'."
  value       = aws_organizations_policy.data_perimeter.arn
}

output "rcp_target_id" {
  description = "Onde a RCP está anexada (por padrão, a conta-membro)."
  value       = aws_organizations_policy_attachment.data_perimeter.target_id
}
