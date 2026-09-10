
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
  description = "Tipo de instancia para os Web Servers (React/Node)."
  type        = string
  default     = "t3.micro"
}

variable "backend_instance_type" {
  description = "Tipo de instancia para o Back-End (Docker/Spring Boot)."
  type        = string
  default     = "t3.small"
}

variable "bastion_instance_type" {
  description = "Tipo de instancia para o Bastion Host."
  type        = string
  default     = "t3.micro"
}


variable "db_instance_class" {
  description = "Classe de instancia do RDS MySQL."
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Nome inicial do banco de dados MySQL."
  type        = string
  default     = "megustadb"
}

variable "db_master_username" {
  description = "Usuario master do RDS MySQL."
  type        = string
  default     = "admin"
}

variable "db_master_user_password" {
  description = "Senha do usuario master do RDS MySQL (minimo 8 caracteres)."
  type        = string
  sensitive   = true
}

variable "db_allocated_storage" {
  description = "Armazenamento alocado (GB) para o RDS MySQL."
  type        = number
  default     = 20
}

variable "instance_type" {
  description = "Tipo de instância EC2 para o webserver."
  type        = string
  default     = "t3.micro"
}
