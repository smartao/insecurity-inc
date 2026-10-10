output "config_bucket_name" {
  description = "Nome do bucket S3 para onde o AWS Config entrega snapshots e histórico de configuração."
  value       = aws_s3_bucket.config.id
}

output "config_bucket_arn" {
  description = "ARN do bucket S3 de destino do delivery channel."
  value       = aws_s3_bucket.config.arn
}

output "configuration_recorder_name" {
  description = "Nome do configuration recorder."
  value       = aws_config_configuration_recorder.main.name
}

output "delivery_channel_name" {
  description = "Nome do delivery channel."
  value       = aws_config_delivery_channel.main.name
}

output "config_service_linked_role_arn" {
  description = "ARN do papel vinculado a serviço (AWSServiceRoleForConfig) usado pelo recorder -- o mesmo que o Security Hub Config.1 exige."
  value       = aws_iam_service_linked_role.config.arn
}

output "config_rule_names" {
  description = "Nome das dez regras gerenciadas deste capítulo, na mesma ordem em que aparecem no main.tf."
  value = [
    aws_config_config_rule.restricted_ssh.name,
    aws_config_config_rule.restricted_common_ports.name,
    aws_config_config_rule.vpc_default_security_group_closed.name,
    aws_config_config_rule.vpc_sg_authorized_ports.name,
    aws_config_config_rule.vpc_flow_logs_enabled.name,
    aws_config_config_rule.secretsmanager_rotation_enabled.name,
    aws_config_config_rule.secretsmanager_scheduled_rotation_success.name,
    aws_config_config_rule.secretsmanager_periodic_rotation.name,
    aws_config_config_rule.secretsmanager_secret_unused.name,
    aws_config_config_rule.secretsmanager_using_cmk.name,
  ]
}
