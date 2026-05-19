data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-private-subnet"
  }
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public.id

  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name = "${var.project_name}-nat-gateway"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route" "public_internet_route" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route" "private_nat_route" {
  route_table_id         = aws_route_table.private_rt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private_rt.id
}

# -------------------------
# EC2
# -------------------------
resource "aws_instance" "bastion_server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  key_name                    = var.key_name
  associate_public_ip_address = true
  private_ip                  = "172.16.10.50" # 172.16.10.10 은 사용중.... 
  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  vpc_security_group_ids = [
    aws_security_group.bastion_sg.id
  ]

  tags = {
    Name = "bastion-server"
    Role = "public-bastion"
  }
}

# 변수에 생성된 서버만큼 생성
resource "aws_instance" "private_servers" {
  for_each = var.private_servers

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.private.id
  key_name                    = var.key_name
  private_ip                  = each.value.private_ip
  associate_public_ip_address = false

  root_block_device {
    volume_size = 15
    volume_type = "gp3"
  }

  iam_instance_profile = each.key == "postgre-db-server" ? aws_iam_instance_profile.db_profile.name : null

  vpc_security_group_ids = [
    aws_security_group.private_server_sg[each.key].id
  ]

  tags = {
    Name = each.key
    Role = "private-server"
  }
}


# =========================
# Ansible Inventory 생성
# =========================

# main.tf - local_file 리소스 수정
# terraform_files에 ansible.cfg와 inventory.yml 저장
# 두 파일들은 terraform apply 시에 s3 bucket에 업로드 된 후, 
# ansible-configure 시에 /ansible_files로 다운로드

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.yml.tpl", {
    bastion_public_ip = aws_instance.bastion_server.public_ip
    # 3-tier 서버의 확장성을 고려하여 ip 주소를 리스트로 선언
    nginx_private_ips   = [aws_instance.private_servers["nginx-fe-server"].private_ip]
    fastapi_private_ips = [aws_instance.private_servers["fastapi-be-server"].private_ip]
    postgre_private_ips = [aws_instance.private_servers["postgre-db-server"].private_ip]
  })
  filename = "${path.module}/inventory.yml"
}


resource "local_file" "ansible_cfg" {
  filename = "${path.module}/ansible.cfg"
  content = templatefile("${path.module}/ansible.cfg.tpl", {
    bastion_ip = aws_instance.bastion_server.public_ip
    gen_path   = path.module
  })
}

# cloud init 등 서버의 다양한 환경 초기화를 위해
# ansible 실행 전 60초 간 대기
resource "terraform_data" "wait_for_instance" {
  depends_on = [
    aws_instance.bastion_server,
    aws_instance.private_servers,
    local_file.ansible_inventory
  ]

  # triggers_replace -> 해당 인자에 변경사항이 생기면, resource를 다시 실행하라
  # concat(
  #   [aws_instance.bastion_server.id],
  #   [for instance in aws_instance.private_servers : instance.id]
  # ) 의 경우엔 4 인스턴스 중 하나라도 아이디가 변경되면 다시 시행하라
  triggers_replace = concat(
    [aws_instance.bastion_server.id],
    [for instance in aws_instance.private_servers : instance.id]
  )

  # linux
  provisioner "local-exec" {
    command = "sleep 60"
  }
}

# 랜덤 ID 생성 (고유한 버킷 이름을 위해 필요)
# resource "random_id" "bucket_suffix" {
#   byte_length = 4
# }

# # DB 백업 전용 S3 버킷 생성
# resource "aws_s3_bucket" "db_backup_bucket" {
#   bucket = "base-pj-ff-backup-${random_id.bucket_suffix.hex}"
#   tags = {
#     Name        = "Monitoring DB Backup"
#     Environment = "Dev"
#   }
# }

# # 앤서블용 환경 변수 파일(s3_env.sh) 생성
# resource "local_file" "s3_env" {
#   content  = "export BUCKET_NAME=\"${aws_s3_bucket.db_backup_bucket.id}\""
  
#   # 핵심 해결책: 어떤 환경에서도 ansible_files 내의 db 역할 폴더를 찾아가도록 설정
#   filename = "${path.module}/../ansible_files/roles/db/files/s3_env.sh"
# }
