output "organization_id" {
  description = "ID da Organization (pré-existente -- este capítulo só lê, nunca gerencia o ciclo de vida dela)."
  value       = data.aws_organizations_organization.this.id
}

output "root_id" {
  description = "ID do Root da Organization."
  value       = data.aws_organizations_organization.this.roots[0].id
}

output "ou_id" {
  description = "ID da OU que recebe as contas-membro e onde a SCP está anexada."
  value       = aws_organizations_organizational_unit.workloads.id
}

output "ou_arn" {
  description = "ARN da OU."
  value       = aws_organizations_organizational_unit.workloads.arn
}

output "scp_policy_id" {
  description = "ID da SCP com os 4 guardrails deste capítulo."
  value       = aws_organizations_policy.baseline_guardrails.id
}

output "scp_policy_arn" {
  description = "ARN da SCP."
  value       = aws_organizations_policy.baseline_guardrails.arn
}

output "member_account_id" {
  description = "Account ID da conta-membro movida para dentro da OU."
  value       = aws_organizations_account.member.id
}
