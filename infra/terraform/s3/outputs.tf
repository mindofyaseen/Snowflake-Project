output "bucket_name" {
  description = "S3 landing bucket name."
  value       = aws_s3_bucket.landing.id
}

output "bucket_arn" {
  description = "S3 landing bucket ARN."
  value       = aws_s3_bucket.landing.arn
}

output "raw_prefix" {
  description = "Base S3 URI for generated raw sources."
  value       = "s3://${aws_s3_bucket.landing.id}/raw/"
}
