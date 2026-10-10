output "console_users_group_name" {
  description = "Nome do grupo IAM ao qual as policies de negócio e de Force MFA estão anexadas."
  value       = aws_iam_group.console_users.name
}

output "force_mfa_policy_arn" {
  description = "ARN da customer-managed policy que nega toda ação da conta, exceto autogestão de senha/MFA, enquanto a sessão não estiver autenticada com MFA."
  value       = aws_iam_policy.force_mfa.arn
}

output "console_users_business_policy_arn" {
  description = "ARN da customer-managed policy de negócio de exemplo (describe de EC2), só exercível de fato com MFA presente."
  value       = aws_iam_policy.console_users_business.arn
}

output "console_analyst_user_name" {
  description = "Nome do usuário IAM de exemplo, membro do grupo que exige MFA."
  value       = aws_iam_user.console_analyst.name
}
