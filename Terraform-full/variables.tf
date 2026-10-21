variable "aws_region" {
  description = "Regiao da AWS onde tudo sera criado."
  type        = string
  default     = "us-east-1"
}

variable "az1" {
  description = "Primeira Zona de Disponibilidade."
  type        = string
  default     = "us-east-1a"
}

variable "az2" {
  description = "Segunda Zona de Disponibilidade."
  type        = string
  default     = "us-east-1b"
}


variable "vpc_cidr" {
  description = "Faixa de IPs da VPC (equivalente ao VpcCidr do megusta-rede.yaml)."
  type        = string
  default     = "10.0.0.0/24"
}

variable "bastion_allowed_cidr" {
  description = "IP (ou faixa de IPs) liberado para acessar o Bastion Host via SSH. Ex: \"meu-ip/32\"."
  type        = string
  default     = "0.0.0.0/0"
}

variable "my_ip" {
  description = "Seu endereço IP (com máscara /32) para permitir acesso HTTP ao webserver. Ex: \"203.0.113.42/32\"."
  type        = string
  default     = "0.0.0.0/0"
}


variable "key_pair_name" {
  description = "Nome do Key Pair EC2 a ser criado."
  type        = string
  default     = "megusta-prod-us1-key"
}


variable "public_key_path" {
  description = "Caminho local do arquivo de chave publica SSH (ex: ./megusta-key.pub) usado para criar o Key Pair na AWS."
  type        = string
  default     = "./megusta-key.pub"
}


variable "web_server_instance_type" {
  description = "Tipo de instancia para os Web Servers (React/Node/Nginx)."
  type        = string
  default     = "t3.small"
}

variable "backend_instance_type" {
  description = "Tipo de instancia para o Back-End (Docker/Spring Boot + RabbitMQ)."
  type        = string
  default     = "t3.medium"
}

variable "bastion_instance_type" {
  description = "Tipo de instancia para o Bastion Host (build das imagens + registry local)."
  type        = string
  default     = "t3.medium"
}

variable "db_instance_type" {
  description = "Tipo de instancia EC2 para o banco de dados MySQL containerizado (apenas AZ A)."
  type        = string
  default     = "t3.medium"
}


variable "instance_type" {
  description = "Tipo de instância EC2 genérico (legado)."
  type        = string
  default     = "t3.micro"
}

variable "lab_instance_profile_name" {
  description = "Nome do LabInstanceProfile existente na conta (ex: LabInstanceProfile). Usado em todas as instancias EC2."
  type        = string
  default     = "LabInstanceProfile"
}

variable "glue_service_role_arn" {
  description = "ARN da role para Glue (se diferente do LabInstanceProfile). Se vazio, tenta usar a role do LabInstanceProfile."
  type        = string
  default     = ""
}

variable "sns_email" {
  description = "E-mail para notificações SNS (CloudWatch Alarms)."
  type        = string
  default     = "henry.silva@sptech.school"
}

# Database credentials for MySQL container
variable "db_root_password" {
  description = "Senha root do MySQL (mínimo 8 caracteres)."
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Senha do usuário da aplicação MySQL (mínimo 8 caracteres)."
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Nome do banco de dados MySQL."
  type        = string
  default     = "megustadb"
}

variable "db_user" {
  description = "Usuário da aplicação MySQL."
  type        = string
  default     = "megusta_user"
}