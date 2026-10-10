output "sns_topic_arn" {
  description = "ARN do tópico SNS que recebe os alertas de NON_COMPLIANT."
  value       = aws_sns_topic.config_compliance_alerts.arn
}

output "event_rule_name" {
  description = "Nome da regra do EventBridge que escuta mudanças de compliance do AWS Config."
  value       = aws_cloudwatch_event_rule.config_non_compliant.name
}

output "event_rule_arn" {
  description = "ARN da regra do EventBridge."
  value       = aws_cloudwatch_event_rule.config_non_compliant.arn
}
