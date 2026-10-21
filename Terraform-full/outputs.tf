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
  description = "ID do Security Group do Banco de Dados (instância EC2)."
  value       = aws_security_group.database.id
}

output "alb_security_group_id" {
  description = "ID do Security Group do Application Load Balancer."
  value       = aws_security_group.alb.id
}


output "key_pair_name" {
  description = "Nome do Key Pair EC2 criado/gerenciado pelo Terraform."
  value       = aws_key_pair.megusta.key_name
}

output "efs_file_system_id" {
  description = "ID do sistema de arquivos EFS."
  value       = aws_efs_file_system.megusta.id
}

output "bastion_host_a_public_ip" {
  description = "Elastic IP do Bastion Host AZ A."
  value       = aws_eip.bastion_host_a.public_ip
}

output "bastion_host_b_public_ip" {
  description = "Elastic IP do Bastion Host AZ B."
  value       = aws_eip.bastion_host_b.public_ip
}

output "nat_gateway_eip" {
  description = "Elastic IP do NAT Gateway."
  value       = aws_eip.nat_gateway.public_ip
}

output "nat_gateway_id" {
  description = "ID do NAT Gateway."
  value       = aws_nat_gateway.main.id
}

output "alb_dns_name" {
  description = "DNS Name do Application Load Balancer."
  value       = aws_lb.megusta.dns_name
}

output "database_a_private_ip" {
  description = "IP privado da instância de banco de dados (AZ A)."
  value       = aws_instance.database_a.private_ip
}

output "web_server_a_private_ip" {
  description = "IP privado do Web Server AZ A."
  value       = aws_instance.web_server_a.private_ip
}

output "web_server_b_private_ip" {
  description = "IP privado do Web Server AZ B."
  value       = aws_instance.web_server_b.private_ip
}

output "backend_a_private_ip" {
  description = "IP privado do Backend AZ A."
  value       = aws_instance.backend_a.private_ip
}

output "backend_b_private_ip" {
  description = "IP privado do Backend AZ B."
  value       = aws_instance.backend_b.private_ip
}


output "s3_raw_bucket_name" {
  description = "Nome do bucket S3 Raw (criado manualmente)."
  value       = data.aws_s3_bucket.raw.bucket
}

output "s3_trusted_bucket_name" {
  description = "Nome do bucket S3 Trusted (criado manualmente)."
  value       = data.aws_s3_bucket.trusted.bucket
}

output "s3_curated_bucket_name" {
  description = "Nome do bucket S3 Curated (criado manualmente)."
  value       = data.aws_s3_bucket.curated.bucket
}

# Glue Outputs
output "glue_database_name" {
  description = "Nome do banco de dados Glue Data Catalog."
  value       = aws_glue_catalog_database.megusta.name
}

output "glue_service_role_arn" {
  description = "ARN da Role IAM do Glue (fornecida via variavel glue_service_role_arn)."
  value       = var.glue_service_role_arn
}

output "glue_raw_crawler_name" {
  description = "Nome do Crawler RAW."
  value       = aws_glue_crawler.raw_crawler.name
}

output "glue_trusted_crawler_name" {
  description = "Nome do Crawler TRUSTED."
  value       = aws_glue_crawler.trusted_crawler.name
}

output "glue_curated_crawler_name" {
  description = "Nome do Crawler CURATED."
  value       = aws_glue_crawler.curated_crawler.name
}

output "glue_logs_crawler_name" {
  description = "Nome do Crawler LOGS."
  value       = aws_glue_crawler.logs_crawler.name
}

output "glue_raw_to_trusted_job_name" {
  description = "Nome do Job Glue RAW -> TRUSTED."
  value       = aws_glue_job.raw_to_trusted.name
}

output "glue_trusted_to_curated_job_name" {
  description = "Nome do Job Glue TRUSTED -> CURATED."
  value       = aws_glue_job.trusted_to_curated.name
}

output "glue_logs_bronze_to_silver_job_name" {
  description = "Nome do Job Glue LOGS Bronze -> Silver."
  value       = aws_glue_job.logs_bronze_to_silver.name
}

# Athena Outputs
output "athena_workgroup_name" {
  description = "Nome do Workgroup Athena."
  value       = aws_athena_workgroup.megusta.name
}

output "athena_results_location" {
  description = "Localização dos resultados do Athena."
  value       = "s3://${data.aws_s3_bucket.curated.bucket}/athena-results/"
}

output "athena_query_role_arn" {
  description = "ARN da Role IAM para execução de queries Athena (usa glue_service_role_arn)."
  value       = var.glue_service_role_arn
}

# Lab Instance Profile Outputs
output "lab_instance_profile_name" {
  description = "Nome do LabInstanceProfile usado nas instancias EC2."
  value       = var.lab_instance_profile_name
}

# CloudWatch/SNS Outputs
output "sns_topic_arn" {
  description = "ARN do tópico SNS para alertas."
  value       = aws_sns_topic.alerts.arn
}

output "cloudwatch_dashboard_name" {
  description = "Nome do dashboard CloudWatch."
  value       = aws_cloudwatch_dashboard.megusta.dashboard_name
}