
resource "aws_security_group" "bastion_host" {
  name        = "bastionhost-sg"
  description = "Libera acesso SSH (porta 22) vindo da internet para o Bastion Host."
  vpc_id      = aws_vpc.minha_vpc.id

  ingress {
    description = "Acesso SSH (defina bastion_allowed_cidr com o seu IP em producao)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.bastion_allowed_cidr]
  }

  egress {
    description = "Libera toda saida"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bastionhost-sg"
  }
}


resource "aws_security_group" "alb" {
  name        = "alb-sg"
  description = "Libera HTTP/HTTPS vindo da internet para o Application Load Balancer."
  vpc_id      = aws_vpc.minha_vpc.id

  ingress {
    description = "HTTP vindo da internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS vindo da internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Libera toda saida"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-sg"
  }
}


resource "aws_security_group" "web_server" {
  name        = "webserver-sg"
  description = "Libera HTTP/HTTPS de dentro da VPC e SSH vindo apenas do Bastion."
  vpc_id      = aws_vpc.minha_vpc.id

  ingress {
    description = "HTTP vindo de dentro da VPC (ex. do ALB)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "HTTPS vindo de dentro da VPC (ex. do ALB)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description     = "SSH somente a partir do Bastion Host"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_host.id]
  }

  egress {
    description = "Libera toda saida"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "webserver-sg"
  }
}


resource "aws_security_group" "backend" {
  name        = "backend-sg"
  description = "Libera a porta da API apenas para quem vem do Web Server, e SSH do Bastion."
  vpc_id      = aws_vpc.minha_vpc.id

  ingress {
    description     = "Porta da API, somente a partir do Web Server"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server.id]
  }

  ingress {
    description     = "SSH somente a partir do Bastion Host"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_host.id]
  }

  egress {
    description = "Libera toda saida"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "backend-sg"
  }
}


resource "aws_security_group" "database" {
  name        = "database-sg"
  description = "Libera a porta do banco apenas para quem vem do Back-End, e SSH do Bastion."
  vpc_id      = aws_vpc.minha_vpc.id

  ingress {
    description     = "Porta do banco (MySQL), somente a partir do Back-End"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
  }

  ingress {
    description     = "SSH somente a partir do Bastion Host"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_host.id]
  }

  egress {
    description = "Libera toda saida"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "database-sg"
  }
}
