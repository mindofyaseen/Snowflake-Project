output "instance_id" {
  description = "EC2 instance ID used by SSM Session Manager."
  value       = aws_instance.airflow.id
}

output "airflow_password_parameter" {
  description = "SecureString parameter populated by cloud-init."
  value       = local.airflow_password_path
}

output "airflow_tunnel_command" {
  description = "Open this SSM tunnel, then browse to http://localhost:8080."
  value       = "aws ssm start-session --profile ${var.aws_profile} --region ${var.aws_region} --target ${aws_instance.airflow.id} --document-name AWS-StartPortForwardingSession --parameters portNumber=8080,localPortNumber=8080"
}

output "password_command" {
  description = "Retrieve the generated Airflow admin password."
  value       = "aws ssm get-parameter --profile ${var.aws_profile} --region ${var.aws_region} --name ${local.airflow_password_path} --with-decryption --query Parameter.Value --output text"
}

