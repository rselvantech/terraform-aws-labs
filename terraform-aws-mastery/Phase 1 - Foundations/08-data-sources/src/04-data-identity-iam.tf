data "aws_caller_identity" "current" {}

data "aws_iam_policy" "s3_read_only" {
  name = var.s3_policy_name
}

data "aws_iam_policy" "ec2_read_only" {
  name = var.ec2_policy_name
}
