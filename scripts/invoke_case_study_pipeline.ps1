[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet("infrastructure", "initial", "incremental", "verify")]
    [string]$Mode,

    [string]$AwsProfile = "default",
    [string]$AwsRegion = "us-east-1",
    [ValidateSet("dev", "test", "prod")]
    [string]$Environment = "dev",
    [datetime]$LoadDate = (Get-Date).ToUniversalTime().Date,
    [int]$InitialNurseCount = 500,
    [int]$IncrementalNurseCount = 550,
    [string]$AirflowInstanceId,
    [string]$S3BucketName,
    [switch]$ApplyInfrastructure,
    [switch]$RunFivetran,
    [switch]$RunHightouch,
    [switch]$SkipDbt
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$platformDir = Join-Path $projectRoot "infra\terraform\platform"
$env:TF_CLI_CONFIG_FILE = Join-Path $projectRoot "infra\terraform\terraform.rc"
$env:TF_DATA_DIR = Join-Path $projectRoot ".terraform-data-platform"
$env:AWS_PROFILE = $AwsProfile
$env:AWS_REGION = $AwsRegion

function Invoke-Checked {
    param([scriptblock]$Command, [string]$FailureMessage)
    & $Command
    if ($LASTEXITCODE -ne 0) { throw $FailureMessage }
}

function Get-PlatformOutput {
    param([string]$Name)
    $value = terraform "-chdir=$platformDir" output -raw $Name
    if ($LASTEXITCODE -ne 0 -or -not $value) { throw "Terraform output '$Name' is unavailable." }
    return $value.Trim()
}

function Invoke-Infrastructure {
    Invoke-Checked { terraform "-chdir=$platformDir" init -input=false } "terraform init failed"
    Invoke-Checked { terraform "-chdir=$platformDir" validate } "terraform validate failed"
    $action = if ($ApplyInfrastructure) { "apply" } else { "plan" }
    $arguments = @(
        "-chdir=$platformDir", $action, "-input=false",
        "-var=aws_profile=$AwsProfile", "-var=aws_region=$AwsRegion",
        "-var=environment=$Environment"
    )
    if ($ApplyInfrastructure) { $arguments += "-auto-approve" }
    Invoke-Checked { terraform @arguments } "terraform $action failed"
}

function Invoke-AirflowBatch {
    param([string]$LoadMode, [int]$NurseCount)
    $instanceId = if ($AirflowInstanceId) { $AirflowInstanceId } else { Get-PlatformOutput "airflow_instance_id" }
    $conf = @{ load_mode = $LoadMode; load_date = $LoadDate.ToString("yyyy-MM-dd"); nurse_count = $NurseCount } | ConvertTo-Json -Compress
    $runId = "carematch_${LoadMode}_$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))"
    $remoteCommand = @"
set -euo pipefail
cd /opt/carematch/project
git fetch origin
git checkout main
git pull --ff-only
docker compose --env-file airflow/.env -f airflow/docker-compose.ec2.yaml exec -T airflow-webserver airflow dags trigger carematch_synthetic_sources_to_s3 --run-id '$runId' --conf '$conf'
for attempt in `$(seq 1 120); do
  state=`$(docker compose --env-file airflow/.env -f airflow/docker-compose.ec2.yaml exec -T airflow-webserver airflow dags state carematch_synthetic_sources_to_s3 '$runId' | tail -n 1 | tr -d '\r')
  if [ "`$state" = "success" ]; then exit 0; fi
  if [ "`$state" = "failed" ]; then exit 1; fi
  sleep 15
done
echo 'Timed out waiting for the Airflow DAG run' >&2
exit 1
"@
    $parameters = @{ commands = @($remoteCommand) } | ConvertTo-Json -Compress
    $commandId = aws ssm send-command --profile $AwsProfile --region $AwsRegion --instance-ids $instanceId --document-name AWS-RunShellScript --parameters $parameters --query Command.CommandId --output text
    if ($LASTEXITCODE -ne 0 -or -not $commandId) { throw "Airflow SSM trigger failed." }
    aws ssm wait command-executed --profile $AwsProfile --region $AwsRegion --command-id $commandId --instance-id $instanceId
    if ($LASTEXITCODE -ne 0) { throw "Airflow trigger command did not complete successfully." }
    aws ssm get-command-invocation --profile $AwsProfile --region $AwsRegion --command-id $commandId --instance-id $instanceId --query "{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}"
}

function Invoke-SnowflakeAndDbt {
    param([string]$BucketName, [bool]$Bootstrap)
    $roleArn = Get-PlatformOutput "snowflake_s3_role_arn_candidate"
    if ($Bootstrap) {
        $bootstrapFile = Join-Path $projectRoot "snowflake\sql\01_platform_bootstrap.sql"
        Invoke-Checked { python (Join-Path $projectRoot "scripts\run_snowflake_sql.py") --bucket $BucketName --snowflake-role-arn $roleArn $bootstrapFile } "Snowflake bootstrap failed"

        $integration = python (Join-Path $projectRoot "scripts\read_snowflake_integration.py") | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0 -or -not $integration.iam_user_arn -or -not $integration.external_id) {
            throw "Could not read the Snowflake storage integration trust values."
        }
        Invoke-Checked {
            terraform "-chdir=$platformDir" apply -auto-approve -input=false `
                "-var=aws_profile=$AwsProfile" "-var=aws_region=$AwsRegion" "-var=environment=$Environment" `
                "-var=enable_snowflake_s3_trust=true" `
                "-var=snowflake_iam_user_arn=$($integration.iam_user_arn)" `
                "-var=snowflake_external_id=$($integration.external_id)"
        } "Snowflake IAM trust apply failed"
    }

    $loadFile = Join-Path $projectRoot "snowflake\sql\02_s3_stage_and_raw_load.sql"
    Invoke-Checked { python (Join-Path $projectRoot "scripts\run_snowflake_sql.py") --bucket $BucketName --snowflake-role-arn $roleArn $loadFile } "Snowflake load failed"

    if (-not $SkipDbt) {
        if (-not (Get-Command dbt -ErrorAction SilentlyContinue)) { throw "dbt is not installed or not on PATH." }
        Invoke-Checked { dbt deps --project-dir (Join-Path $projectRoot "dbt") --profiles-dir (Join-Path $projectRoot "dbt") } "dbt deps failed"
        Invoke-Checked { dbt build --project-dir (Join-Path $projectRoot "dbt") --profiles-dir (Join-Path $projectRoot "dbt") } "dbt build failed"
    }
}

function Invoke-FivetranSync {
    if (-not $env:FIVETRAN_APIKEY -or -not $env:FIVETRAN_APISECRET -or -not $env:FIVETRAN_CONNECTOR_ID) {
        throw "Set FIVETRAN_APIKEY, FIVETRAN_APISECRET, and FIVETRAN_CONNECTOR_ID."
    }
    $pair = "$($env:FIVETRAN_APIKEY):$($env:FIVETRAN_APISECRET)"
    $token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
    Invoke-RestMethod -Method Post -Uri "https://api.fivetran.com/v1/connectors/$($env:FIVETRAN_CONNECTOR_ID)/force" -Headers @{ Authorization = "Basic $token" } | Out-Null
}

function Invoke-HightouchSync {
    if (-not $env:HIGHTOUCH_API_KEY -or -not $env:HIGHTOUCH_SYNC_ID) {
        throw "Set HIGHTOUCH_API_KEY and HIGHTOUCH_SYNC_ID."
    }
    Invoke-RestMethod -Method Post -Uri "https://api.hightouch.com/api/v1/syncs/$($env:HIGHTOUCH_SYNC_ID)/trigger" -Headers @{ Authorization = "Bearer $($env:HIGHTOUCH_API_KEY)" } | Out-Null
}

Push-Location $projectRoot
try {
    if ($Mode -eq "infrastructure") {
        Invoke-Infrastructure
        return
    }

    Invoke-Checked { python -m unittest discover -s tests -v } "Local validation failed"
    $bucket = if ($S3BucketName) { $S3BucketName } else { Get-PlatformOutput "s3_bucket_name" }

    if ($Mode -in @("initial", "incremental")) {
        $isInitial = $Mode -eq "initial"
        $count = if ($isInitial) { $InitialNurseCount } else { $IncrementalNurseCount }
        if ($PSCmdlet.ShouldProcess("CareMatch $Environment", "Run $Mode pipeline with $count nurses")) {
            Invoke-AirflowBatch -LoadMode $Mode -NurseCount $count
            Invoke-SnowflakeAndDbt -BucketName $bucket -Bootstrap $isInitial
            if ($RunFivetran) { Invoke-FivetranSync }
            if ($RunHightouch) { Invoke-HightouchSync }
        }
    }

    if ($Mode -eq "verify") {
        Invoke-Checked { python (Join-Path $projectRoot "scripts\run_snowflake_sql.py") --bucket $bucket (Join-Path $projectRoot "snowflake\sql\06_incremental_demo.sql") } "Verification query failed"
    }
}
finally {
    Pop-Location
}
