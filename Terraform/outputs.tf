
output "vpc_id" {
  description = "ID da VPC criada."
  value       = aws_vpc.minha_vpc.id
}

output "bastion_host_security_group_id" {
  description = "ID do Security Group do Bastion Host."
  value       = aws_security_group.bastion_host.id
}

output "web_server_security_group_id" {
  description = "ID do Security Group dos Web Servers."
  value       = aws_security_group.web_server.id
}

output "backend_security_group_id" {
  description = "ID do Security Group do Back-End."
  value       = aws_security_group.backend.id
}

output "database_security_group_id" {
  description = "ID do Security Group do Banco de Dados."
  value       = aws_security_group.database.id
}

output "alb_security_group_id" {
  description = "ID do Security Group do Application Load Balancer."
  value       = aws_security_group.alb.id
}


output "key_pair_name" {
  description = "Nome do Key Pair criado."
  value       = aws_key_pair.megusta.key_name
}

output "efs_file_system_id" {
  description = "ID do sistema de arquivos EFS."
  value       = aws_efs_file_system.megusta.id
}

output "bastion_host_public_ip" {
  description = "Elastic IP do Bastion Host."
  value       = aws_eip.bastion_host.public_ip
}

output "alb_dns_name" {
  description = "DNS Name do Application Load Balancer."
  value       = aws_lb.megusta.dns_name
}

output "rds_endpoint" {
  description = "Endpoint do RDS MySQL."
  value       = aws_db_instance.megusta.address
}
