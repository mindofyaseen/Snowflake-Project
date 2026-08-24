output "snowflake_s3_role_arn" {
  description = "IAM role ARN referenced by CAREMATCH_S3_INT."
  value       = aws_iam_role.snowflake_s3.arn
}

output "allowed_s3_prefix" {
  description = "S3 prefix readable by Snowflake."
  value       = "s3://${var.bucket_name}/raw/"
}
