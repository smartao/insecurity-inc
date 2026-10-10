output "checkout_app_instance_ids" {
  description = "IDs das instâncias EC2 que representam a aplicação de checkout — as únicas instâncias que a policy autoriza o plantão a start/stop/reboot."
  value       = { for name, instance in aws_instance.checkout_app : name => instance.id }
}

output "oncall_sysops_group_name" {
  description = "Nome do grupo IAM ao qual a policy least-privilege está anexada (RBAC)."
  value       = aws_iam_group.oncall_sysops.name
}

output "oncall_sysops_policy_arn" {
  description = "ARN da customer-managed policy least-privilege criada para o grupo de plantão."
  value       = aws_iam_policy.oncall_sysops.arn
}

output "oncall_analyst_user_name" {
  description = "Nome do usuário IAM de exemplo que representa o analista de plantão, membro do grupo."
  value       = aws_iam_user.oncall_analyst.name
}
