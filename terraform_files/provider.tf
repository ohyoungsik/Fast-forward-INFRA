terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # terraform 상태관리를 위한 remote 백엔드 설정. s3와 DynamoDB 생성 O(5/12)
  backend "s3" {
    bucket       = "fastforward-tfstate"
    key          = "prod/terraform.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.aws_region
}