output "reports_bucket_name" {
  description = "Nome do bucket S3 que representa o recurso alvo da policy least-privilege."
  value       = aws_s3_bucket.reports.bucket
}

output "report_analysts_group_name" {
  description = "Nome do grupo IAM ao qual a policy least-privilege está anexada (RBAC)."
  value       = aws_iam_group.report_analysts.name
}

output "reports_analyst_policy_arn" {
  description = "ARN da customer-managed policy least-privilege criada para o grupo de analistas."
  value       = aws_iam_policy.reports_analyst.arn
}

output "report_analyst_user_name" {
  description = "Nome do usuário IAM de exemplo que representa a analista de dados, membro do grupo."
  value       = aws_iam_user.report_analyst.name
}
