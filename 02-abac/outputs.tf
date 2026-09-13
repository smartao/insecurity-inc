output "team_reports_bucket_name" {
  description = "Nome do bucket S3 compartilhado, particionado por prefixo/pasta (um por time)."
  value       = aws_s3_bucket.team_reports.bucket
}

output "abac_team_reports_policy_arn" {
  description = "ARN da customer-managed policy ABAC única, compartilhada por todos os times."
  value       = aws_iam_policy.abac_team_reports.arn
}

output "abac_analysts_group_name" {
  description = "Nome do grupo IAM ao qual a policy ABAC está anexada."
  value       = aws_iam_group.abac_analysts.name
}

output "team_analyst_user_names" {
  description = "Nomes dos usuários IAM de exemplo (um por time), cada um com a tag access-project correspondente."
  value       = { for team, user in aws_iam_user.team_analyst : team => user.name }
}
