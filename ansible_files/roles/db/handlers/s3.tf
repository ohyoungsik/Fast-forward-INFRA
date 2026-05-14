# 1. AWS 서울 리전 및 키 설정 (하드코딩 방식)
provider "aws" {
  region     = "ap-northeast-2"
  access_key = "awskey"
  secret_key = "aws"
}

# 2. 랜덤 ID 생성 (전 세계 S3 버킷 이름 겹침 완벽 방지)
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# 3. 대망의 DB 백업 전용 S3 버킷 생성
resource "aws_s3_bucket" "db_backup_bucket" {
  # 이름설정-랜덤숫자 형태로 고유한 이름 생성
  bucket = "base-pj-ff-backup-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "Monitoring DB Backup"
    Environment = "Dev"
  }
}

# 4. fast-mgmt 서버가 찰 '보안 신분증(IAM Role)' 목걸이 생성
resource "aws_iam_role" "ec2_s3_backup_role" {
  name = "ktcloud-ec2-s3-backup-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# 5. 그 신분증에 'S3 자유이용권(FullAccess)' 권한 스티커 붙이기
resource "aws_iam_role_policy_attachment" "s3_full_access" {
  role       = aws_iam_role.ec2_s3_backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# 6. EC2에 목걸이를 걸어주기 위한 연결고리(Instance Profile) 만들기
resource "aws_iam_instance_profile" "ec2_s3_backup_profile" {
  name = "ktcloud-ec2-s3-backup-profile"
  role = aws_iam_role.ec2_s3_backup_role.name
}

# 7. (보너스) 실행 완료 후 생성된 버킷 이름을 화면에 출력해 달라는 명령어
output "created_bucket_name" {
  value = aws_s3_bucket.db_backup_bucket.id
  description = "생성된 S3 버킷의 이름입니다. 나중에 이 이름을 사용하세요!"
}