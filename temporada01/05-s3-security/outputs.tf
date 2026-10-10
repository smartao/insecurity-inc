output "bucket_name" {
  description = "Nome completo do bucket S3 de exemplo (prefixo + sufixo aleatório usado para garantir unicidade global)."
  value       = aws_s3_bucket.customer_receipts.id
}

output "bucket_arn" {
  description = "ARN do bucket S3 de exemplo."
  value       = aws_s3_bucket.customer_receipts.arn
}
