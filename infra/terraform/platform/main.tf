data "aws_caller_identity" "current" {}

locals {
  snowflake_s3_role_name = "carematch-${var.environment}-snowflake-s3"
}

module "s3" {
  source = "../s3"

  providers = { aws = aws }

  aws_profile = var.aws_profile
  aws_region  = var.aws_region
  environment = var.environment
}

module "airflow" {
  source = "../ec2-airflow"

  providers = { aws = aws }

  aws_profile    = var.aws_profile
  aws_region     = var.aws_region
  environment    = var.environment
  s3_bucket_name = module.s3.bucket_name
  instance_type  = var.airflow_instance_type
  repository_url = var.repository_url
  repository_ref = var.repository_ref
}

module "snowflake_s3_trust" {
  count  = var.enable_snowflake_s3_trust ? 1 : 0
  source = "../snowflake-s3-integration"

  providers = { aws = aws }

  aws_profile            = var.aws_profile
  aws_region             = var.aws_region
  environment            = var.environment
  bucket_name            = module.s3.bucket_name
  role_name              = local.snowflake_s3_role_name
  snowflake_iam_user_arn = var.snowflake_iam_user_arn
  snowflake_external_id  = var.snowflake_external_id
}

module "fivetran_schedule" {
  count  = var.enable_fivetran_schedule ? 1 : 0
  source = "../fivetran-schedule"

  providers = { fivetran = fivetran }

  connector_id      = var.fivetran_connector_id
  sync_frequency    = var.fivetran_sync_frequency
  paused            = false
  pause_after_trial = var.pause_fivetran_after_trial
}
