output "kms_key_id" {
  description = "ID da CMK usada para cifrar o bucket de recibos."
  value       = aws_kms_key.customer_receipts.key_id
}

output "kms_key_arn" {
  description = "ARN da CMK usada para cifrar o bucket de recibos."
  value       = aws_kms_key.customer_receipts.arn
}

output "kms_alias_name" {
  description = "Alias amigável da CMK."
  value       = aws_kms_alias.customer_receipts.name
}

output "bucket_name" {
  description = "Nome completo do bucket S3 de exemplo (prefixo + sufixo aleatório usado para garantir unicidade global)."
  value       = aws_s3_bucket.customer_receipts.id
}

output "bucket_arn" {
  description = "ARN do bucket S3 de exemplo."
  value       = aws_s3_bucket.customer_receipts.arn
}
