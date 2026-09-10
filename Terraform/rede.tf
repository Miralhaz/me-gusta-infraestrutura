
resource "aws_vpc" "minha_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "minha-vpc"
  }
}


resource "aws_internet_gateway" "meu_internet_gateway" {
  vpc_id = aws_vpc.minha_vpc.id

  tags = {
    Name = "meu-internet-gateway"
  }
}



resource "aws_subnet" "publica_a" {
  vpc_id                  = aws_vpc.minha_vpc.id
  availability_zone       = var.az1
  cidr_block               = "10.0.0.0/26"
  map_public_ip_on_launch = true

  tags = {
    Name = "subnet-publica-us-east-1a"
  }
}

resource "aws_subnet" "publica_b" {
  vpc_id                  = aws_vpc.minha_vpc.id
  availability_zone       = var.az2
  cidr_block               = "10.0.0.64/26"
  map_public_ip_on_launch = true

  tags = {
    Name = "subnet-publica-us-east-1b"
  }
}



resource "aws_subnet" "privada_web_a" {
  vpc_id                  = aws_vpc.minha_vpc.id
  availability_zone       = var.az1
  cidr_block               = "10.0.0.128/27"
  map_public_ip_on_launch = false

  tags = {
    Name = "subnet-privada-web-us-east-1a"
  }
}

resource "aws_subnet" "privada_web_b" {
  vpc_id                  = aws_vpc.minha_vpc.id
  availability_zone       = var.az2
  cidr_block               = "10.0.0.160/27"
  map_public_ip_on_launch = false

  tags = {
    Name = "subnet-privada-web-us-east-1b"
  }
}



resource "aws_subnet" "privada_backend" {
  vpc_id                  = aws_vpc.minha_vpc.id
  availability_zone       = var.az1
  cidr_block               = "10.0.0.192/27"
  map_public_ip_on_launch = false

  tags = {
    Name = "subnet-privada-backend-us-east-1a"
  }
}



resource "aws_subnet" "privada_database_a" {
  vpc_id                  = aws_vpc.minha_vpc.id
  availability_zone       = var.az1
  cidr_block               = "10.0.0.224/28"
  map_public_ip_on_launch = false

  tags = {
    Name = "subnet-privada-database-us-east-1a"
  }
}

resource "aws_subnet" "privada_database_b" {
  vpc_id                  = aws_vpc.minha_vpc.id
  availability_zone       = var.az2
  cidr_block               = "10.0.0.240/28"
  map_public_ip_on_launch = false

  tags = {
    Name = "subnet-privada-database-us-east-1b"
  }
}


resource "aws_eip" "nat_eip" {
  domain = "vpc"

  depends_on = [aws_internet_gateway.meu_internet_gateway]

  tags = {
    Name = "meu-nat-eip"
  }
}

resource "aws_nat_gateway" "meu_nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.publica_a.id

  tags = {
    Name = "meu-nat-gateway"
  }
}



resource "aws_route_table" "publica" {
  vpc_id = aws_vpc.minha_vpc.id

  tags = {
    Name = "route-table-publica"
  }
}

resource "aws_route" "para_internet" {
  route_table_id         = aws_route_table.publica.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id              = aws_internet_gateway.meu_internet_gateway.id
}

resource "aws_route_table_association" "publica_a" {
  subnet_id      = aws_subnet.publica_a.id
  route_table_id = aws_route_table.publica.id
}

resource "aws_route_table_association" "publica_b" {
  subnet_id      = aws_subnet.publica_b.id
  route_table_id = aws_route_table.publica.id
}


resource "aws_route_table" "privada" {
  vpc_id = aws_vpc.minha_vpc.id

  tags = {
    Name = "route-table-privada"
  }
}

resource "aws_route" "para_nat" {
  route_table_id         = aws_route_table.privada.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id          = aws_nat_gateway.meu_nat_gateway.id
}

resource "aws_route_table_association" "privada_web_a" {
  subnet_id      = aws_subnet.privada_web_a.id
  route_table_id = aws_route_table.privada.id
}

resource "aws_route_table_association" "privada_web_b" {
  subnet_id      = aws_subnet.privada_web_b.id
  route_table_id = aws_route_table.privada.id
}

resource "aws_route_table_association" "privada_backend" {
  subnet_id      = aws_subnet.privada_backend.id
  route_table_id = aws_route_table.privada.id
}

resource "aws_route_table_association" "privada_database_a" {
  subnet_id      = aws_subnet.privada_database_a.id
  route_table_id = aws_route_table.privada.id
}

resource "aws_route_table_association" "privada_database_b" {
  subnet_id      = aws_subnet.privada_database_b.id
  route_table_id = aws_route_table.privada.id
}
