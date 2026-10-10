output "vpc_id" {
  description = "ID da VPC do laboratório."
  value       = aws_vpc.lab.id
}

output "subnet_id" {
  description = "ID da subnet pública do laboratório. Usada no teste opcional para lançar a instância que gera tráfego real."
  value       = aws_subnet.lab.id
}

output "flow_log_id" {
  description = "ID do flow log (fl-...)."
  value       = aws_flow_log.vpc.id
}

output "log_group_name" {
  description = "Nome do CloudWatch Log Group para onde os registros são publicados."
  value       = aws_cloudwatch_log_group.vpc_flow_logs.name
}

output "log_group_arn" {
  description = "ARN do CloudWatch Log Group, exatamente como o atributo `arn` do Terraform o expõe -- SEM o \":*\" final que a API bruta (describe-log-groups) devolve. Ver comentário em main.tf sobre por que a política do papel IAM acrescenta esse sufixo à mão."
  value       = aws_cloudwatch_log_group.vpc_flow_logs.arn
}

output "flow_logs_role_arn" {
  description = "ARN do papel IAM que o serviço de flow logs assume para publicar no log group."
  value       = aws_iam_role.flow_logs.arn
}
