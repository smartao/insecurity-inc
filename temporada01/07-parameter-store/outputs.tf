# Nenhum output expõe "value" de parâmetro -- só nome/ARN. O valor em si só
# deve ser lido sob demanda (ssm get-parameter --with-decryption), nunca
# impresso de forma incidental num "terraform output" ou "terraform apply".

output "checkout_backend_role_arn" {
  description = "ARN da role da aplicação de checkout, usada para os testes de 'sts assume-role' do README."
  value       = aws_iam_role.checkout_backend.arn
}

output "checkout_backend_role_name" {
  description = "Nome da role da aplicação de checkout."
  value       = aws_iam_role.checkout_backend.name
}

output "checkout_backend_policy_arn" {
  description = "ARN da IAM policy de leitura escopada ao prefixo do checkout."
  value       = aws_iam_policy.checkout_backend_parameter_read.arn
}

output "parameter_path_prefix" {
  description = "Prefixo hierárquico usado pelos parâmetros deste capítulo."
  value       = var.parameter_path_prefix
}

output "db_password_parameter_name" {
  description = "Nome (não o valor) do parâmetro SecureString com a senha do banco."
  value       = aws_ssm_parameter.db_password.name
}

output "payment_gateway_api_key_parameter_name" {
  description = "Nome (não o valor) do parâmetro SecureString com a API key do gateway de pagamento."
  value       = aws_ssm_parameter.payment_gateway_api_key.name
}

output "checkout_v2_enabled_parameter_name" {
  description = "Nome do parâmetro String (não sensível) da feature flag do checkout v2."
  value       = aws_ssm_parameter.checkout_v2_enabled.name
}
