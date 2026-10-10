output "team_app_instance_ids" {
  description = "IDs das instâncias EC2 de exemplo, uma por time — cada uma tagueada com access-project = <time>."
  value       = { for team, instance in aws_instance.team_app : team => instance.id }
}

output "abac_team_apps_policy_arn" {
  description = "ARN da customer-managed policy ABAC única, compartilhada por todos os times."
  value       = aws_iam_policy.abac_team_apps.arn
}

output "abac_analysts_group_name" {
  description = "Nome do grupo IAM ao qual a policy ABAC está anexada."
  value       = aws_iam_group.abac_analysts.name
}

output "team_analyst_user_names" {
  description = "Nomes dos usuários IAM de exemplo (um por time), cada um com a tag access-project correspondente."
  value       = { for team, user in aws_iam_user.team_analyst : team => user.name }
}
