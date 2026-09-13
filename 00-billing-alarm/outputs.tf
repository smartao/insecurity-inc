output "billing_alerts_sns_topic_arn" {
  description = "ARN do tópico SNS que recebe as notificações do CloudWatch Billing Alarm."
  value       = aws_sns_topic.billing_alerts.arn
}

output "billing_alarm_name" {
  description = "Nome do CloudWatch Alarm sobre a métrica AWS/Billing EstimatedCharges."
  value       = aws_cloudwatch_metric_alarm.billing_estimated_charges.alarm_name
}

output "monthly_budget_name" {
  description = "Nome do AWS Budget mensal configurado para a conta."
  value       = aws_budgets_budget.monthly_cost.name
}
