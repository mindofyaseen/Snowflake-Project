param(
    [string]$AwsProfile = 'carematch-dev',
    [string]$Region = 'us-east-1',
    [ValidateSet('dev', 'test', 'prod')]
    [string]$Environment = 'dev'
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$TerraformDir = Join-Path $ProjectRoot 'infra\terraform\s3'
$env:TF_CLI_CONFIG_FILE = Join-Path $ProjectRoot 'infra\terraform\terraform.rc'
$env:TF_DATA_DIR = Join-Path $ProjectRoot '.terraform-data-s3'
$env:AWS_PROFILE = $AwsProfile
$env:AWS_REGION = $Region

Push-Location $ProjectRoot
try {
    python -m src.generate_healthcare_data --output data/generated
    python -m unittest discover -s tests -v

    terraform "-chdir=$TerraformDir" fmt -check
    terraform "-chdir=$TerraformDir" init -input=false
    terraform "-chdir=$TerraformDir" validate
    terraform "-chdir=$TerraformDir" apply -auto-approve -input=false `
        -var "aws_profile=$AwsProfile" `
        -var "aws_region=$Region" `
        -var "environment=$Environment"

    $BucketName = terraform "-chdir=$TerraformDir" output -raw bucket_name
    if ($LASTEXITCODE -ne 0 -or -not $BucketName) { throw 'Terraform bucket output was not available.' }

    & (Join-Path $ProjectRoot 'scripts\upload_to_s3.ps1') `
        -BucketName $BucketName -AwsProfile $AwsProfile -Region $Region -Apply
}
finally {
    Pop-Location
}
