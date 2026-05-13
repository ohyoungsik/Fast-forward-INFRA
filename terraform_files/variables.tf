variable "aws_region" {
  default = "ap-northeast-2"
}

variable "project_name" {
  default = "testfor-log-monitoring"
}

variable "vpc_cidr" {
  default = "172.16.0.0/16"
}

variable "public_subnet_cidr" {
  default = "172.16.10.0/24"
}

variable "private_subnet_cidr" {
  default = "172.16.20.0/24"
}

variable "availability_zone" {
  default = "ap-northeast-2a"
}

variable "key_name" {
  description = "EC2 key pair name"
  type = string
  default = "FF-test-key"
}

variable "instance_type" {
  default = "t3.small"
}

variable "private_servers" {
  default = {
    testfor-nginx-fe-server = {
      private_ip = "172.16.20.10"
    }

    testfor-fastapi-be-server = {
      private_ip = "172.16.20.20"
    }

    testfor-postgre-db-server = {
      private_ip = "172.16.20.30"
    }
  }
}