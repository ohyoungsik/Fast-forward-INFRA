resource "aws_iam_instance_profile" "db_profile" {
  name = "base-pj-ff-db-profile"
  role = "EC2-S3-ACCESS-ROLE"
}