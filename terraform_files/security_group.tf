resource "aws_security_group" "bastion_sg" {
  name        = "${var.project_name}-bastion-sg"
  description = "Security group for bastion server"
  vpc_id      = aws_vpc.main.id

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

# ── Bastion SG ingress rules ──────────────────────────────────────────────────

resource "aws_security_group_rule" "bastion_ssh" {
  type              = "ingress"
  description       = "SSH from my IP"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.bastion_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "bastion_http" {
  type              = "ingress"
  description       = "HTTP from internet for reverse proxy"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.bastion_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "bastion_https" {
  type              = "ingress"
  description       = "HTTPS from internet"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.bastion_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "fastapi_to_prometheus" {
  type                     = "ingress"
  description              = "Prometheus from FastAPI server"
  from_port                = 9090
  to_port                  = 9090
  protocol                 = "tcp"
  security_group_id        = aws_security_group.bastion_sg.id
  source_security_group_id = aws_security_group.private_server_sg["fastapi-be-server"].id
}

resource "aws_security_group_rule" "prometheus_from_my_ip" {
  type              = "ingress"
  description       = "Prometheus from my IP"
  from_port         = 9090
  to_port           = 9090
  protocol          = "tcp"
  security_group_id = aws_security_group.bastion_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "grafana_from_my_ip" {
  type              = "ingress"
  description       = "Grafana from my IP"
  from_port         = 3000
  to_port           = 3000
  protocol          = "tcp"
  security_group_id = aws_security_group.bastion_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
}

# ── Private server SG ingress rules ──────────────────────────────────────────

resource "aws_security_group_rule" "private_ssh_from_bastion" {
  for_each = var.private_servers

  type                     = "ingress"
  description              = "SSH from bastion"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.private_server_sg[each.key].id
  source_security_group_id = aws_security_group.bastion_sg.id
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
# 프로메테우스 가 각각 서버에 대해서 데이터를 가져오는 인바운드 규칙
resource "aws_security_group_rule" "bastion_to_private_node_exporter" {
  for_each = var.private_servers

  type                     = "ingress"
  description              = "Node Exporter from bastion prometheus"
  from_port                = 9100
  to_port                  = 9100
  protocol                 = "tcp"
  security_group_id        = aws_security_group.private_server_sg[each.key].id
  source_security_group_id = aws_security_group.bastion_sg.id
}