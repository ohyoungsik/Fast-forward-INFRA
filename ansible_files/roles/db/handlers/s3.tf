# AWS 서울 리전 및 키 설정 (GitHub Actions가 인증 키 주입)
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

# 테라폼이 쉘 스크립트용 환경 변수 파일 생성
resource "local_file" "s3_env" {
  # 쉘 스크립트에서 바로 쓸 수 있게 'export' 문법으로 작성
  content  = "export BUCKET_NAME=\"${aws_s3_bucket.db_backup_bucket.id}\""
  filename = "../ansible_files/roles/db/files/s3_env.sh"
}