output "access_analyzer_arn" {
  description = "ARN do external access analyzer da conta."
  value       = aws_accessanalyzer_analyzer.external_access.arn
}

output "access_analyzer_name" {
  description = "Nome do external access analyzer da conta."
  value       = aws_accessanalyzer_analyzer.external_access.analyzer_name
}

output "external_audit_role_arn" {
  description = "ARN da role de auditoria externa, com trust policy escopada à conta configurada em var.external_account_id + External ID."
  value       = aws_iam_role.external_audit.arn
}

output "external_audit_role_name" {
  description = "Nome da role de auditoria externa."
  value       = aws_iam_role.external_audit.name
}
