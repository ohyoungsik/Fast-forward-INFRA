resource "aws_security_group" "bastion_sg" {
  name        = "${var.project_name}-bastion-sg"
  description = "Security group for bastion server"
  vpc_id      = aws_vpc.main.id

 
  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 해당 부분을 내 IP로만 하면 내 IP 만 ssh 접속이 가능 우선은 테스트
  }

  ingress {
    description = "HTTP from internet for reverse proxy"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-bastion-sg"
  }
}

resource "aws_security_group" "private_server_sg" {
  for_each = var.private_servers

  name        = "${var.project_name}-${each.key}-sg"
  description = "Security group for ${each.key}"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${each.key}-sg"
  }
}

resource "aws_security_group_rule" "bastion_to_nginx_http" {
  type                     = "ingress"
  description              = "HTTP from bastion reverse proxy"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.private_server_sg["nginx-fe-server"].id
  source_security_group_id = aws_security_group.bastion_sg.id
}

resource "aws_security_group_rule" "nginx_to_fastapi" {
  type                     = "ingress"
  description              = "FastAPI from nginx frontend"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  security_group_id        = aws_security_group.private_server_sg["fastapi-be-server"].id
  source_security_group_id = aws_security_group.private_server_sg["nginx-fe-server"].id
}

resource "aws_security_group_rule" "fastapi_to_postgres" {
  type                     = "ingress"
  description              = "PostgreSQL from FastAPI server"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.private_server_sg["postgre-db-server"].id
  source_security_group_id = aws_security_group.private_server_sg["fastapi-be-server"].id
}