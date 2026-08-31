output "s3_bucket_name" {
  description = "Private raw-data landing bucket."
  value       = module.s3.bucket_name
}

output "airflow_instance_id" {
  description = "EC2 instance running Airflow."
  value       = module.airflow.instance_id
}

output "airflow_tunnel_command" {
  description = "SSM port-forward command for the Airflow UI."
  value       = module.airflow.airflow_tunnel_command
}

output "airflow_password_command" {
  description = "Command that retrieves the generated Airflow password."
  value       = module.airflow.password_command
}

output "snowflake_s3_role_arn" {
  description = "IAM role assumed by Snowflake when the optional trust module is enabled."
  value       = try(module.snowflake_s3_trust[0].snowflake_s3_role_arn, null)
}

output "snowflake_s3_role_arn_candidate" {
  description = "Stable role ARN used to create the Snowflake integration before the trust handshake."
  value       = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.snowflake_s3_role_name}"
}

output "fivetran_connector_id" {
  description = "Managed Fivetran connector ID when enabled."
  value       = try(module.fivetran_schedule[0].connector_id, null)
}
