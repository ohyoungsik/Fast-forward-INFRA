# AWS 서울 리전 및 키 설정
provider "aws" {
  region     = "ap-northeast-2"
}

# 랜덤 ID 생성
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# DB 백업 전용 S3 버킷 생성
resource "aws_s3_bucket" "db_backup_bucket" {
  # 이름설정-랜덤숫자 형태로 고유한 이름 생성
  bucket = "base-pj-ff-backup-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "Monitoring DB Backup"
    Environment = "Dev"
  }
}

