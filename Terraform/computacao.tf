
resource "aws_key_pair" "megusta" {
  key_name   = var.key_pair_name
  public_key = file(var.public_key_path)

  tags = {
    Name = "megusta-prod-us1-keypair"
  }
}


resource "aws_efs_file_system" "megusta" {
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  tags = {
    Name = "megusta-prod-us1-efs"
  }
}

resource "aws_efs_mount_target" "web_a" {
  file_system_id  = aws_efs_file_system.megusta.id
  subnet_id       = aws_subnet.privada_web_a.id
  security_groups = [aws_security_group.web_server.id]
}

resource "aws_efs_mount_target" "web_b" {
  file_system_id  = aws_efs_file_system.megusta.id
  subnet_id       = aws_subnet.privada_web_b.id
  security_groups = [aws_security_group.web_server.id]
}


resource "aws_instance" "bastion_host" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.bastion_instance_type
  key_name               = aws_key_pair.megusta.key_name
  subnet_id              = aws_subnet.publica_a.id
  vpc_security_group_ids = [aws_security_group.bastion_host.id]

  tags = {
    Name = "megusta-prod-us1-bastion-host"
  }
}

resource "aws_eip" "bastion_host" {
  domain   = "vpc"
  instance = aws_instance.bastion_host.id

  tags = {
    Name = "megusta-prod-us1-bastion-eip"
  }
}


resource "aws_instance" "web_server_1b" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.web_server_instance_type
  key_name               = aws_key_pair.megusta.key_name
  subnet_id              = aws_subnet.privada_web_b.id
  vpc_security_group_ids = [aws_security_group.web_server.id]

  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<html><body><h1>Hello World from Web 1b-1!</h1></body></html>" > /var/www/html/index.html
              EOF

  tags = {
    Name = "megusta-prod-us1-web-1b-1"
  }
}

resource "aws_instance" "web_server_1b_2" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.web_server_instance_type
  key_name               = aws_key_pair.megusta.key_name
  subnet_id              = aws_subnet.privada_web_b.id
  vpc_security_group_ids = [aws_security_group.web_server.id]

  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<html><body><h1>Hello World from Web 1b-2!</h1></body></html>" > /var/www/html/index.html
              EOF

  tags = {
    Name = "megusta-prod-us1-web-1b-2"
  }
}


resource "aws_instance" "web_server_1a" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.web_server_instance_type
  key_name               = aws_key_pair.megusta.key_name
  subnet_id              = aws_subnet.privada_web_a.id
  vpc_security_group_ids = [aws_security_group.web_server.id]

  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<html><body><h1>Hello World from Web 1a-1!</h1></body></html>" > /var/www/html/index.html
              EOF

  tags = {
    Name = "megusta-prod-us1-web-1a-1"
  }
}

resource "aws_instance" "web_server_1a_2" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.web_server_instance_type
  key_name               = aws_key_pair.megusta.key_name
  subnet_id              = aws_subnet.privada_web_a.id
  vpc_security_group_ids = [aws_security_group.web_server.id]

  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<html><body><h1>Hello World from Web 1a-2!</h1></body></html>" > /var/www/html/index.html
              EOF

tags = {
    Name = "megusta-prod-us1-web-1a-2"
  }
}

resource "aws_instance" "backend" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.backend_instance_type
  key_name               = aws_key_pair.megusta.key_name
  subnet_id              = aws_subnet.privada_backend.id
  vpc_security_group_ids = [aws_security_group.backend.id]

  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y java-21-amazon-corretto docker
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ec2-user
              EOF

  tags = {
    Name = "megusta-prod-us1-backend"
  }
}

resource "aws_lb" "megusta" {
  name               = "megusta-prod-us1-alb"
  load_balancer_type = "application"
  ip_address_type    = "ipv4"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.publica_a.id, aws_subnet.publica_b.id]

  tags = {
    Name = "megusta-prod-us1-alb"
  }
}

resource "aws_lb_target_group" "megusta" {
  name     = "megusta-prod-us1-tg"
  protocol = "HTTP"
  port     = 80
  vpc_id   = aws_vpc.minha_vpc.id

  health_check {
    protocol            = "HTTP"
    path                = "/"
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name = "megusta-prod-us1-tg"
  }
}


resource "aws_lb_target_group_attachment" "web_server_1b" {
  target_group_arn = aws_lb_target_group.megusta.arn
  target_id        = aws_instance.web_server_1b.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "web_server_1b_2" {
  target_group_arn = aws_lb_target_group.megusta.arn
  target_id        = aws_instance.web_server_1b_2.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "web_server_1a" {
  target_group_arn = aws_lb_target_group.megusta.arn
  target_id        = aws_instance.web_server_1a.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "web_server_1a_2" {
  target_group_arn = aws_lb_target_group.megusta.arn
  target_id        = aws_instance.web_server_1a_2.id
  port             = 80
}

resource "aws_lb_listener" "megusta" {
  load_balancer_arn = aws_lb.megusta.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.megusta.arn
  }
}


resource "aws_db_subnet_group" "megusta" {
  name        = "megusta-prod-us1-db-subnet-group"
  description = "Subnet group para o RDS MySQL Multi-AZ do MeGusta"
  subnet_ids = [
    aws_subnet.privada_database_a.id,
    aws_subnet.privada_database_b.id,
  ]

  tags = {
    Name = "megusta-prod-us1-db-subnet-group"
  }
}


resource "aws_db_instance" "megusta" {
  identifier     = "megusta-prod-us1-rds"
  engine         = "mysql"
  instance_class = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"

  db_name  = var.db_name
  username = var.db_master_username
  password = var.db_master_user_password

  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.megusta.name
  vpc_security_group_ids = [aws_security_group.database.id]

  publicly_accessible     = false
  backup_retention_period = 7


  skip_final_snapshot       = false
  final_snapshot_identifier = "megusta-prod-us1-rds-final-snapshot"

  tags = {
    Name = "megusta-prod-us1-rds"
  }
}
