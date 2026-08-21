param(
    [Parameter(Mandatory = $true)]
    [string]$BucketName,
    [string]$AwsProfile = 'carematch-dev',
    [string]$Region = 'us-east-1',
    [string]$DataDirectory = 'data\generated',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ResolvedData = Join-Path $ProjectRoot $DataDirectory

if (-not (Test-Path -LiteralPath (Join-Path $ResolvedData 'manifest.json'))) {
    throw "Generated manifest not found: $ResolvedData\manifest.json"
}

aws sts get-caller-identity --profile $AwsProfile --region $Region | Out-Null
if ($LASTEXITCODE -ne 0) { throw "AWS profile validation failed: $AwsProfile" }

aws s3api head-bucket --bucket $BucketName --profile $AwsProfile --region $Region
if ($LASTEXITCODE -ne 0) { throw "S3 bucket is unavailable: $BucketName" }

$Arguments = @(
    's3', 'sync', $ResolvedData, "s3://$BucketName/raw/",
    '--profile', $AwsProfile,
    '--region', $Region,
    '--sse', 'AES256',
    '--exclude', 'manifest.json'
)
if (-not $Apply) { $Arguments += '--dryrun' }

& aws @Arguments
if ($LASTEXITCODE -ne 0) { throw 'S3 data sync failed.' }

if ($Apply) {
    aws s3 cp (Join-Path $ResolvedData 'manifest.json') "s3://$BucketName/raw/manifest.json" `
        --profile $AwsProfile --region $Region --sse AES256 `
        --content-type application/json
    if ($LASTEXITCODE -ne 0) { throw 'Manifest upload failed.' }
    aws s3api head-object --bucket $BucketName --key 'raw/manifest.json' `
        --profile $AwsProfile --region $Region | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Remote manifest verification failed.' }
    Write-Host "Upload verified: s3://$BucketName/raw/manifest.json"
}
else {
    Write-Host 'Dry run complete. Re-run with -Apply to upload.'
}
