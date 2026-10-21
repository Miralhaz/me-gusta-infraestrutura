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
  description = "Libera HTTP/HTTPS de qualquer IPv4 (internet/ALB) e SSH vindo apenas do Bastion."
  vpc_id      = aws_vpc.minha_vpc.id

  ingress {
    description = "HTTP vindo de qualquer IPv4 (internet/ALB)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS vindo de qualquer IPv4 (internet/ALB)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
  description = "Libera a porta da API apenas para quem vem do Web Server, e SSH do Bastion. Regras de RabbitMQ (self-referencing) sao criadas via aws_security_group_rule."
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

# RabbitMQ Self-Referencing Rules (clustering entre backend_a e backend_b)
resource "aws_security_group_rule" "backend_rabbitmq_amqp" {
  type                     = "ingress"
  from_port                = 5672
  to_port                  = 5672
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.backend.id
  security_group_id        = aws_security_group.backend.id
  description              = "RabbitMQ AMQP - clustering entre backends"
}

resource "aws_security_group_rule" "backend_rabbitmq_amqp_tls" {
  type                     = "ingress"
  from_port                = 5671
  to_port                  = 5671
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.backend.id
  security_group_id        = aws_security_group.backend.id
  description              = "RabbitMQ AMQP TLS - clustering entre backends"
}

resource "aws_security_group_rule" "backend_rabbitmq_mgmt" {
  type                     = "ingress"
  from_port                = 15672
  to_port                  = 15672
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.backend.id
  security_group_id        = aws_security_group.backend.id
  description              = "RabbitMQ Management UI - clustering entre backends"
}

resource "aws_security_group_rule" "backend_rabbitmq_erlang_dist" {
  type                     = "ingress"
  from_port                = 25672
  to_port                  = 25672
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.backend.id
  security_group_id        = aws_security_group.backend.id
  description              = "RabbitMQ Erlang Distribution - clustering entre backends"
}

resource "aws_security_group_rule" "backend_rabbitmq_epmd" {
  type                     = "ingress"
  from_port                = 4369
  to_port                  = 4369
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.backend.id
  security_group_id        = aws_security_group.backend.id
  description              = "RabbitMQ EPMD - clustering entre backends"
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

# =============================================================================
# Docker Swarm - comunicação entre os nós
# =============================================================================
# Sem estas regras o "docker swarm join" falha e a rede overlay (VXLAN) não
# funciona, impedindo frontend -> backend -> database de se comunicarem.
#   - 2377/tcp : cluster management (join)
#   - 7946/tcp : node communication (gossip)
#   - 7946/udp : node communication (gossip)
#   - 4789/udp : overlay network (VXLAN)
# Liberado para a faixa da VPC (todos os nós do cluster).
locals {
  swarm_node_sgs = [
    aws_security_group.bastion_host.id,
    aws_security_group.web_server.id,
    aws_security_group.backend.id,
    aws_security_group.database.id,
  ]
}

resource "aws_security_group_rule" "swarm_management" {
  count             = length(local.swarm_node_sgs)
  type              = "ingress"
  from_port         = 2377
  to_port           = 2377
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = local.swarm_node_sgs[count.index]
  description       = "Docker Swarm - cluster management"
}

resource "aws_security_group_rule" "swarm_gossip_tcp" {
  count             = length(local.swarm_node_sgs)
  type              = "ingress"
  from_port         = 7946
  to_port           = 7946
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = local.swarm_node_sgs[count.index]
  description       = "Docker Swarm - node communication (TCP)"
}

resource "aws_security_group_rule" "swarm_gossip_udp" {
  count             = length(local.swarm_node_sgs)
  type              = "ingress"
  from_port         = 7946
  to_port           = 7946
  protocol          = "udp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = local.swarm_node_sgs[count.index]
  description       = "Docker Swarm - node communication (UDP)"
}

resource "aws_security_group_rule" "swarm_overlay_vxlan" {
  count             = length(local.swarm_node_sgs)
  type              = "ingress"
  from_port         = 4789
  to_port           = 4789
  protocol          = "udp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = local.swarm_node_sgs[count.index]
  description       = "Docker Swarm - overlay network (VXLAN)"
}

# Local Registry (roda no manager na porta 5000). Os workers precisam puxar as
# imagens de "$MANAGER_IP:5000", entao liberamos a porta apenas dentro da VPC.
resource "aws_security_group_rule" "swarm_registry" {
  type              = "ingress"
  from_port         = 5000
  to_port           = 5000
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.bastion_host.id
  description       = "Local Registry - workers puxam imagens do manager"
}


