param(
    [Parameter(Mandatory = $true)]
    [string]$BucketName,
    [string]$Profile = "carematch-dev",
    [string]$Region = "us-east-1",
    [ValidateSet("plan", "apply")]
    [string]$Action = "plan"
)

$ErrorActionPreference = "Stop"
$env:AWS_PROFILE = $Profile
$env:AWS_REGION = $Region
$terraformDirectory = Join-Path $PSScriptRoot "..\infra\terraform\ec2-airflow"

terraform "-chdir=$terraformDirectory" init
$arguments = @(
    "-chdir=$terraformDirectory",
    $Action,
    "-var=aws_profile=$Profile",
    "-var=aws_region=$Region",
    "-var=s3_bucket_name=$BucketName"
)
if ($Action -eq "apply") { $arguments += "-auto-approve" }
terraform @arguments

if ($Action -eq "apply") {
    Write-Host "Cloud-init and SSM registration normally take 10-15 minutes."
    terraform "-chdir=$terraformDirectory" output airflow_tunnel_command
    terraform "-chdir=$terraformDirectory" output password_command
}
