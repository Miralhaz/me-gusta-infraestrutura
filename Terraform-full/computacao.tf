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


locals {
  FLUENTBIT_VERSION = "3.1.5"

  fluentbit_user_data = templatefile("${path.module}/templates/fluentbit_user_data.tpl", {
    raw_bucket        = data.aws_s3_bucket.raw.bucket
    hostname          = "HOSTNAME"
    FLUENTBIT_VERSION = local.FLUENTBIT_VERSION
  })

  database_user_data = templatefile("${path.module}/templates/database_user_data.tpl", {
    raw_bucket        = data.aws_s3_bucket.raw.bucket
    hostname          = "database-a"
    db_root_password  = var.db_root_password
    db_name           = var.db_name
    db_user           = var.db_user
    db_password       = var.db_password
    FLUENTBIT_VERSION = local.FLUENTBIT_VERSION
  })

  bastion_a_user_data = templatefile("${path.module}/templates/bastion_user_data.tpl", {
    raw_bucket        = data.aws_s3_bucket.raw.bucket
    hostname          = "bastion-host-a"
    FLUENTBIT_VERSION = local.FLUENTBIT_VERSION
  })

  bastion_b_user_data = templatefile("${path.module}/templates/bastion_user_data.tpl", {
    raw_bucket        = data.aws_s3_bucket.raw.bucket
    hostname          = "bastion-host-b"
    FLUENTBIT_VERSION = local.FLUENTBIT_VERSION
  })

  web_a_user_data = templatefile("${path.module}/templates/web_user_data.tpl", {
    raw_bucket        = data.aws_s3_bucket.raw.bucket
    hostname          = "web-a"
    FLUENTBIT_VERSION = local.FLUENTBIT_VERSION
  })

  web_b_user_data = templatefile("${path.module}/templates/web_user_data.tpl", {
    raw_bucket        = data.aws_s3_bucket.raw.bucket
    hostname          = "web-b"
    FLUENTBIT_VERSION = local.FLUENTBIT_VERSION
  })

  backend_a_user_data = templatefile("${path.module}/templates/backend_user_data.tpl", {
    raw_bucket        = data.aws_s3_bucket.raw.bucket
    hostname          = "backend-a"
    FLUENTBIT_VERSION = local.FLUENTBIT_VERSION
  })

  backend_b_user_data = templatefile("${path.module}/templates/backend_user_data.tpl", {
    raw_bucket        = data.aws_s3_bucket.raw.bucket
    hostname          = "backend-b"
    FLUENTBIT_VERSION = local.FLUENTBIT_VERSION
  })
}


resource "aws_instance" "bastion_host_a" {
  ami                    = data.aws_ami.ubuntu_2204.id
  instance_type          = var.bastion_instance_type
  key_name               = aws_key_pair.megusta.key_name
  subnet_id              = aws_subnet.publica_a.id
  vpc_security_group_ids = [aws_security_group.bastion_host.id]
  iam_instance_profile   = var.lab_instance_profile_name

  user_data                   = local.bastion_a_user_data
  user_data_replace_on_change = true

  # Disco maior: o bastion roda o registry local e faz build das 4 imagens
  # (frontend/backend/database/rabbitmq), o que consome bastante espaco.
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name = "megusta-prod-us1-bastion-host-a"
    Role = "bastion-manager"
  }
}

resource "aws_eip" "bastion_host_a" {
  domain   = "vpc"
  instance = aws_instance.bastion_host_a.id

  tags = {
    Name = "megusta-prod-us1-bastion-a-eip"
  }
}


resource "aws_instance" "bastion_host_b" {
  ami                    = data.aws_ami.ubuntu_2204.id
  instance_type          = var.bastion_instance_type
  key_name               = aws_key_pair.megusta.key_name
  subnet_id              = aws_subnet.publica_b.id
  vpc_security_group_ids = [aws_security_group.bastion_host.id]
  iam_instance_profile   = var.lab_instance_profile_name

  user_data                   = local.bastion_b_user_data
  user_data_replace_on_change = true

  # Disco maior: o bastion roda o registry local e faz build das 4 imagens
  # (frontend/backend/database/rabbitmq), o que consome bastante espaco.
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name = "megusta-prod-us1-bastion-host-b"
    Role = "bastion-manager"
  }
}

resource "aws_eip" "bastion_host_b" {
  domain   = "vpc"
  instance = aws_instance.bastion_host_b.id

  tags = {
    Name = "megusta-prod-us1-bastion-b-eip"
  }
}


# NAT Gateway - Single, highly available, managed by AWS
resource "aws_eip" "nat_gateway" {
  domain = "vpc"
  tags = {
    Name = "megusta-prod-us1-nat-gateway-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat_gateway.id
  subnet_id     = aws_subnet.publica_a.id

  tags = {
    Name = "megusta-prod-us1-nat-gateway"
  }

  # Wait for NAT Gateway to be available before creating routes
  depends_on = [aws_internet_gateway.meu_internet_gateway]
}

# Route for AZ A private subnets -> NAT Gateway
resource "aws_route" "nat_private_a" {
  route_table_id         = aws_route_table.privada_a.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

# Route for AZ B private subnets -> NAT Gateway
resource "aws_route" "nat_private_b" {
  route_table_id         = aws_route_table.privada_b.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}


resource "aws_instance" "web_server_a" {
  ami                    = data.aws_ami.ubuntu_2204.id
  instance_type          = var.web_server_instance_type
  key_name               = aws_key_pair.megusta.key_name
  subnet_id              = aws_subnet.privada_web_a.id
  vpc_security_group_ids = [aws_security_group.web_server.id]
  iam_instance_profile   = var.lab_instance_profile_name

  user_data                   = local.web_a_user_data
  user_data_replace_on_change = true

  # Espera o NAT Gateway + rotas privadas existirem antes do boot. Sem isto o
  # user_data roda sem Internet e nenhum pacote consegue ser baixado.
  depends_on = [aws_route.nat_private_a, aws_route.nat_private_b]

  tags = {
    Name = "megusta-prod-us1-web-a"
    Role = "frontend"
  }
}

resource "aws_instance" "web_server_b" {
  ami                    = data.aws_ami.ubuntu_2204.id
  instance_type          = var.web_server_instance_type
  key_name               = aws_key_pair.megusta.key_name
  subnet_id              = aws_subnet.privada_web_b.id
  vpc_security_group_ids = [aws_security_group.web_server.id]
  iam_instance_profile   = var.lab_instance_profile_name

  user_data                   = local.web_b_user_data
  user_data_replace_on_change = true

  # Espera o NAT Gateway + rotas privadas existirem antes do boot.
  depends_on = [aws_route.nat_private_a, aws_route.nat_private_b]

  tags = {
    Name = "megusta-prod-us1-web-b"
    Role = "frontend"
  }
}

resource "aws_instance" "backend_a" {
  ami                    = data.aws_ami.ubuntu_2204.id
  instance_type          = var.backend_instance_type
  key_name               = aws_key_pair.megusta.key_name
  subnet_id              = aws_subnet.privada_backend_a.id
  vpc_security_group_ids = [aws_security_group.backend.id]
  iam_instance_profile   = var.lab_instance_profile_name

  user_data                   = local.backend_a_user_data
  user_data_replace_on_change = true

  # Espera o NAT Gateway + rotas privadas existirem antes do boot.
  depends_on = [aws_route.nat_private_a, aws_route.nat_private_b]

  tags = {
    Name = "megusta-prod-us1-backend-a"
    Role = "backend"
  }
}

resource "aws_instance" "backend_b" {
  ami                    = data.aws_ami.ubuntu_2204.id
  instance_type          = var.backend_instance_type
  key_name               = aws_key_pair.megusta.key_name
  subnet_id              = aws_subnet.privada_backend_b.id
  vpc_security_group_ids = [aws_security_group.backend.id]
  iam_instance_profile   = var.lab_instance_profile_name

  user_data                   = local.backend_b_user_data
  user_data_replace_on_change = true

  # Espera o NAT Gateway + rotas privadas existirem antes do boot.
  depends_on = [aws_route.nat_private_a, aws_route.nat_private_b]

  tags = {
    Name = "megusta-prod-us1-backend-b"
    Role = "backend"
  }
}


resource "aws_instance" "database_a" {
  ami                    = data.aws_ami.ubuntu_2204.id
  instance_type          = var.db_instance_type
  key_name               = aws_key_pair.megusta.key_name
  subnet_id              = aws_subnet.privada_database_a.id
  vpc_security_group_ids = [aws_security_group.database.id]
  iam_instance_profile   = var.lab_instance_profile_name

  user_data                   = local.database_user_data
  user_data_replace_on_change = true

  # Espera o NAT Gateway + rotas privadas existirem antes do boot.
  depends_on = [aws_route.nat_private_a, aws_route.nat_private_b]

  tags = {
    Name = "megusta-prod-us1-database-a"
    Role = "database"
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
    path                = "/health"
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name = "megusta-prod-us1-tg"
  }
}

resource "aws_lb_target_group_attachment" "web_server_a" {
  target_group_arn = aws_lb_target_group.megusta.arn
  target_id        = aws_instance.web_server_a.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "web_server_b" {
  target_group_arn = aws_lb_target_group.megusta.arn
  target_id        = aws_instance.web_server_b.id
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