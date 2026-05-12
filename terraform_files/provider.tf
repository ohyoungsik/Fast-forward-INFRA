terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # terraform 상태관리를 위한 remote 백엔드 설정. 아직 s3와 DynamoDB 생성 X
    # backend "s3" {
    #     bucket = "tfstate-bucket-9bdb5a88" # 미리 생성한 s3 버킷의 이름
    #     key = "test01/terraform.tfstate" # /test01/하위에 만들어지도록
    #     region = "ap-northeast-2"
    #     dynamodb_table = "terraform-lock-test01"
    #     encrypt = true # tfstate에는 민감한 정보가 있을 수 있기 때문에 암호화
    # }
}

provider "aws" {
  region = var.aws_region
}