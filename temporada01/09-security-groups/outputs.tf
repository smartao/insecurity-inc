output "vpc_id" {
  description = "ID da VPC do laboratório."
  value       = aws_vpc.lab.id
}

output "default_security_group_id" {
  description = "ID do default security group da VPC, esvaziado (zero regras) pelo Terraform."
  value       = aws_default_security_group.lab.id
}

output "web_security_group_id" {
  description = "ID do security group da camada web (a única com regra aberta à internet: HTTPS)."
  value       = aws_security_group.web.id
}

output "app_security_group_id" {
  description = "ID do security group da camada app (só aceita a camada web)."
  value       = aws_security_group.app.id
}

output "db_security_group_id" {
  description = "ID do security group da camada de banco (só aceita a camada app)."
  value       = aws_security_group.db.id
}

output "web_network_interface_id" {
  description = "ID da interface de rede de exemplo da camada web, usada no teste opcional de alcançabilidade."
  value       = aws_network_interface.web.id
}

output "app_network_interface_id" {
  description = "ID da interface de rede de exemplo da camada app, usada no teste opcional de alcançabilidade."
  value       = aws_network_interface.app.id
}

output "db_network_interface_id" {
  description = "ID da interface de rede de exemplo da camada de banco, usada no teste opcional de alcançabilidade."
  value       = aws_network_interface.db.id
}
