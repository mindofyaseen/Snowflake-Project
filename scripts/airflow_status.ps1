param(
    [string]$Profile = "carematch-dev",
    [string]$Region = "us-east-1"
)

$ErrorActionPreference = "Stop"
$terraformDirectory = Join-Path $PSScriptRoot "..\infra\terraform\ec2-airflow"
$instanceId = terraform "-chdir=$terraformDirectory" output -raw instance_id

aws ssm describe-instance-information `
    --profile $Profile `
    --region $Region `
    --filters "Key=InstanceIds,Values=$instanceId" `
    --query "InstanceInformationList[0].{InstanceId:InstanceId,PingStatus:PingStatus,Platform:PlatformName,AgentVersion:AgentVersion}"

Write-Host "Airflow tunnel:"
terraform "-chdir=$terraformDirectory" output -raw airflow_tunnel_command

