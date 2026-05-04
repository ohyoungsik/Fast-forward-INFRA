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

# pem 파일 관련 작업
# 알고리즘 결정
resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
# 키등록
resource "aws_key_pair" "kp" {
  key_name   = var.key_name
  public_key = tls_private_key.pk.public_key_openssh
}
# 개인키 가져오기
resource "local_file" "project_key_pem" {
  filename        = "${path.module}/${var.key_name}.pem"
  content         = tls_private_key.pk.private_key_pem
  file_permission = "0600"
}

# -------------------------
# EC2
# -------------------------
resource "aws_instance" "bastion_server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  key_name                    = aws_key_pair.kp.key_name
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
  key_name                    = aws_key_pair.kp.key_name
  private_ip                  = each.value.private_ip
  associate_public_ip_address = false

  root_block_device {
    volume_size = 15  
    volume_type = "gp3"
  }

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

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/inventory.yml"

  content = yamlencode({
    all = {
      children = {
        bastion = {
          hosts = {
            "bastion-server" = {
              ansible_host                 = aws_instance.bastion_server.public_ip
              ansible_user                 = "ubuntu"
              ansible_ssh_private_key_file = "${path.module}/base-project-key.pem"
            }
          }
        }

        private = {
          hosts = {
            for name, instance in aws_instance.private_servers :
            name => {
              ansible_host                 = instance.private_ip
              ansible_user                 = "ubuntu"
              ansible_ssh_private_key_file = "${path.module}/base-project-key.pem"

              ansible_ssh_common_args = "-o ProxyCommand=\"ssh -W %h:%p -i ${path.module}/base-project-key.pem -o StrictHostKeyChecking=no ubuntu@${aws_instance.bastion_server.public_ip}\""
            }
          }
        }
      }
    }
  })
}

resource "terraform_data" "wait_for_instance" {
  depends_on = [
    aws_instance.bastion_server,
    aws_instance.private_servers,
    local_file.ansible_inventory
  ]

  triggers_replace = concat(
    [aws_instance.bastion_server.id],
    [for instance in aws_instance.private_servers : instance.id]
  )

  # windows 
  provisioner "local-exec" {
    command     = "Start-Sleep -Seconds 60"
    interpreter = ["PowerShell", "-Command"]
  }

  # linux
  #    provisioner "local-exec" {
  #    command = "sleep 60"
  #  }
}


# 우선 주석 처리 
# resource "terraform_data" "ansible_run" {
#   depends_on = [terraform_data.wait_for_instance]

#   triggers_replace = concat(
#     [aws_instance.bastion_server.id],
#     [for instance in aws_instance.private_servers : instance.id]
#   )

#   provisioner "local-exec" {
#     command     = "ansible-playbook -i ../terraform_files/inventory.yml site.yml"
#     working_dir = "${path.module}/../ansible_files"
#   }
# }