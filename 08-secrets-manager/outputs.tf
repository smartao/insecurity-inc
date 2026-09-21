# Nenhum output expõe o valor do secret -- só nome/ARN. O valor só deve ser
# lido sob demanda (secretsmanager get-secret-value), nunca impresso de forma
# incidental num "terraform output" ou "terraform apply".

output "secret_arn" {
  description = "ARN completo do secret de credenciais do banco (inclui o sufixo aleatório que o Secrets Manager acrescenta ao nome)."
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "secret_name" {
  description = "Nome (não o valor) do secret de credenciais do banco."
  value       = aws_secretsmanager_secret.db_credentials.name
}

output "checkout_backend_role_arn" {
  description = "ARN da role da aplicação de checkout, usada para os testes de 'sts assume-role' do README."
  value       = aws_iam_role.checkout_backend.arn
}

output "checkout_backend_role_name" {
  description = "Nome da role da aplicação de checkout."
  value       = aws_iam_role.checkout_backend.name
}

output "checkout_backend_policy_arn" {
  description = "ARN da IAM policy de leitura escopada a este secret."
  value       = aws_iam_policy.checkout_backend_secret_read.arn
}

output "rotation_function_name" {
  description = "Nome da Lambda que rotaciona o secret."
  value       = aws_lambda_function.rotation.function_name
}

output "rotation_log_group_name" {
  description = "Log group da Lambda de rotação, para acompanhar as quatro etapas da rotação no CloudWatch Logs."
  value       = aws_cloudwatch_log_group.rotation.name
}

output "rotation_days" {
  description = "Intervalo, em dias, da rotação automática."
  value       = var.rotation_days
}
