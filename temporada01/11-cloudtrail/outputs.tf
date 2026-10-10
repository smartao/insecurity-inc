output "trail_arn" {
  description = "ARN do trail (montado à mão em locals.trail_arn, não lido do recurso -- ver comentário em main.tf)."
  value       = aws_cloudtrail.main.arn
}

output "trail_name" {
  description = "Nome do trail."
  value       = aws_cloudtrail.main.name
}

output "cloudtrail_bucket_name" {
  description = "Nome do bucket S3 para onde o trail entrega os arquivos de log e os digests de validação de integridade."
  value       = aws_s3_bucket.cloudtrail_logs.id
}

output "cloudtrail_bucket_arn" {
  description = "ARN do bucket S3 de logs do trail."
  value       = aws_s3_bucket.cloudtrail_logs.arn
}

output "access_logs_bucket_name" {
  description = "Nome do bucket S3 que recebe o access logging do bucket de logs do trail (Security Hub CloudTrail.7)."
  value       = aws_s3_bucket.access_logs.id
}

output "cloudwatch_log_group_name" {
  description = "Nome do CloudWatch Log Group para onde o trail publica uma cópia em tempo real dos eventos."
  value       = aws_cloudwatch_log_group.cloudtrail.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN do CloudWatch Log Group, exatamente como o atributo `arn` do Terraform o expõe -- ver capítulo 10 para a divergência frente à API bruta (`describe-log-groups`), que vale igual aqui."
  value       = aws_cloudwatch_log_group.cloudtrail.arn
}

output "cloudtrail_cloudwatch_role_arn" {
  description = "ARN do papel IAM que o CloudTrail assume para publicar no CloudWatch Log Group."
  value       = aws_iam_role.cloudtrail_cloudwatch_logs.arn
}
