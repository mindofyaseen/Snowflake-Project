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
    [string]$SnowflakeRoleArn,
    [switch]$ApplyInfrastructure,
    [switch]$RunFivetran,
    [switch]$RunHightouch,
    [switch]$SkipDbt,
    [int]$SaasTimeoutSeconds = 1800,
    [int]$SaasPollIntervalSeconds = 30
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
  state=`$(docker compose --env-file airflow/.env -f airflow/docker-compose.ec2.yaml exec -T airflow-webserver bash -c "airflow dags list-runs -d carematch_synthetic_sources_to_s3 -o json | python3 -c \"import json, sys; runs = json.load(sys.stdin); print(next((r['state'] for r in runs if r['run_id'] == '$runId'), 'unknown'))\"" | tr -d '\r')
  echo "  attempt ${attempt}: DAG state=${state}"
  if [ "${state}" = "success" ]; then exit 0; fi
  if [ "${state}" = "failed" ]; then exit 1; fi
  sleep 15
done
echo 'Timed out waiting for the Airflow DAG run' >&2
exit 1
"@
    $parameters = @{ commands = @($remoteCommand) } | ConvertTo-Json -Compress
    Write-Host "[Airflow] Sending SSM command to instance $instanceId..."
    $tempParamFile = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($tempParamFile, $parameters, [System.Text.UTF8Encoding]::new($false))
        $commandId = aws ssm send-command `
            --profile $AwsProfile --region $AwsRegion `
            --instance-ids $instanceId `
            --document-name AWS-RunShellScript `
            --parameters "file://$tempParamFile" `
            --query Command.CommandId --output text 2>&1
    } finally {
        if (Test-Path $tempParamFile) { Remove-Item $tempParamFile -Force }
    }
    if ($LASTEXITCODE -ne 0 -or -not $commandId) {
        throw "Airflow SSM send-command failed: $commandId"
    }
    $commandId = $commandId.Trim()
    Write-Host "[Airflow] SSM command ID: $commandId - polling for completion..."

    aws ssm wait command-executed `
        --profile $AwsProfile --region $AwsRegion `
        --command-id $commandId --instance-id $instanceId 2>&1 | Out-Null
    $ssmExitCode = $LASTEXITCODE

    $invocationRaw = aws ssm get-command-invocation `
        --profile $AwsProfile --region $AwsRegion `
        --command-id $commandId --instance-id $instanceId `
        --query "{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}" `
        --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to retrieve SSM invocation details for command ${commandId}: $invocationRaw"
    }
    try {
        $invocation = $invocationRaw | ConvertFrom-Json
    } catch {
        throw "SSM invocation output was not valid JSON: $invocationRaw"
    }

    Write-Host "[Airflow] SSM status: $($invocation.Status)"
    if ($invocation.Output) { Write-Host "[Airflow] stdout:`n$($invocation.Output)" }
    if ($invocation.Error -and $invocation.Error.Trim()) { Write-Host "[Airflow] stderr:`n$($invocation.Error)" }

    if ($ssmExitCode -ne 0 -or $invocation.Status -ne "Success") {
        throw "Airflow DAG run failed (SSM status=$($invocation.Status), exitCode=$ssmExitCode)."
    }
    Write-Host "[Airflow] PASS - DAG run $runId succeeded."
}

function Invoke-SnowflakeAndDbt {
    param([string]$BucketName, [bool]$Bootstrap)
    $roleArn = if ($SnowflakeRoleArn) {
        $SnowflakeRoleArn
    } elseif ($Bootstrap) {
        Get-PlatformOutput "snowflake_s3_role_arn_candidate"
    } else {
        try { Get-PlatformOutput "snowflake_s3_role_arn_candidate" } catch { "" }
    }

    if ($Bootstrap) {
        $bootstrapFile = Join-Path $projectRoot "snowflake\sql\01_platform_bootstrap.sql"
        Invoke-Checked {
            python (Join-Path $projectRoot "scripts\run_snowflake_sql.py") `
                --bucket $BucketName --snowflake-role-arn $roleArn $bootstrapFile
        } "Snowflake bootstrap failed"

        $integrationRaw = python (Join-Path $projectRoot "scripts\read_snowflake_integration.py") 2>&1
        if ($LASTEXITCODE -ne 0) { throw "read_snowflake_integration.py failed: $integrationRaw" }
        try {
            $integration = $integrationRaw | ConvertFrom-Json
        } catch {
            throw "read_snowflake_integration.py output was not valid JSON: $integrationRaw"
        }
        if (-not $integration.iam_user_arn -or -not $integration.external_id) {
            throw "Could not read Snowflake storage integration trust values."
        }
        Invoke-Checked {
            terraform "-chdir=$platformDir" apply -auto-approve -input=false `
                "-var=aws_profile=$AwsProfile" "-var=aws_region=$AwsRegion" `
                "-var=environment=$Environment" `
                "-var=enable_snowflake_s3_trust=true" `
                "-var=snowflake_iam_user_arn=$($integration.iam_user_arn)" `
                "-var=snowflake_external_id=$($integration.external_id)"
        } "Snowflake IAM trust apply failed"
    }

    $loadFile = Join-Path $projectRoot "snowflake\sql\02_s3_stage_and_raw_load.sql"
    Invoke-Checked {
        python (Join-Path $projectRoot "scripts\run_snowflake_sql.py") `
            --bucket $BucketName --snowflake-role-arn $roleArn $loadFile
    } "Snowflake load failed"
    Write-Host "[Snowflake] PASS - raw load complete."

    if (-not $SkipDbt) {
        if (-not (Get-Command dbt -ErrorAction SilentlyContinue)) { throw "dbt is not installed or not on PATH." }
        $packagesFile = Join-Path $projectRoot "dbt\packages.yml"
        if (Test-Path $packagesFile) {
            Invoke-Checked {
                dbt deps --project-dir (Join-Path $projectRoot "dbt") --profiles-dir (Join-Path $projectRoot "dbt")
            } "dbt deps failed"
        } else {
            Write-Host "[dbt] No packages.yml declared - skipping dbt deps."
        }
        Invoke-Checked {
            dbt build --project-dir (Join-Path $projectRoot "dbt") --profiles-dir (Join-Path $projectRoot "dbt")
        } "dbt build failed"
        Write-Host "[dbt] PASS - models built and tests passed."
    }
}

function Invoke-FivetranSync {
    param(
        [int]$TimeoutSeconds = $SaasTimeoutSeconds,
        [int]$PollInterval = $SaasPollIntervalSeconds
    )
    $missing = @()
    if (-not $env:FIVETRAN_APIKEY)        { $missing += "FIVETRAN_APIKEY" }
    if (-not $env:FIVETRAN_APISECRET)     { $missing += "FIVETRAN_APISECRET" }
    if (-not $env:FIVETRAN_CONNECTOR_ID)  { $missing += "FIVETRAN_CONNECTOR_ID" }
    if ($missing.Count -gt 0) {
        throw "Missing Fivetran environment variables: $($missing -join ', '). Set them and retry."
    }

    Write-Host "[Fivetran] Triggering and polling connector $($env:FIVETRAN_CONNECTOR_ID)..."
    Invoke-Checked {
        python (Join-Path $projectRoot "scripts\saas_sync.py") fivetran `
            --timeout $TimeoutSeconds --interval $PollInterval
    } "Fivetran sync failed"
    Write-Host "[Fivetran] PASS - connector sync completed successfully."
}

function Invoke-HightouchSync {
    param(
        [int]$TimeoutSeconds = $SaasTimeoutSeconds,
        [int]$PollInterval = $SaasPollIntervalSeconds
    )
    $missing = @()
    if (-not $env:HIGHTOUCH_API_KEY) { $missing += "HIGHTOUCH_API_KEY" }
    if (-not $env:HIGHTOUCH_SYNC_ID) { $missing += "HIGHTOUCH_SYNC_ID" }
    if ($missing.Count -gt 0) {
        throw "Missing Hightouch environment variables: $($missing -join ', '). Set them and retry."
    }

    Write-Host "[Hightouch] Triggering and polling sync $($env:HIGHTOUCH_SYNC_ID)..."
    Invoke-Checked {
        python (Join-Path $projectRoot "scripts\saas_sync.py") hightouch `
            --timeout $TimeoutSeconds --interval $PollInterval
    } "Hightouch sync failed"
    Write-Host "[Hightouch] PASS - sync completed successfully."
}

Push-Location $projectRoot
try {
    if ($Mode -eq "infrastructure") {
        Invoke-Infrastructure
        return
    }

    Write-Host "[Validate] Running local unit tests..."
    Invoke-Checked { python -m unittest discover -s tests -v } "Local validation failed"
    Write-Host "[Validate] PASS - all unit tests passed."

    $bucket = if ($S3BucketName) { $S3BucketName } else { Get-PlatformOutput "s3_bucket_name" }

    if ($Mode -in @("initial", "incremental")) {
        $isInitial = $Mode -eq "initial"
        $count = if ($isInitial) { $InitialNurseCount } else { $IncrementalNurseCount }
        if ($PSCmdlet.ShouldProcess("CareMatch $Environment", "Run $Mode pipeline with $count nurses")) {
            Write-Host "[Pipeline] Starting $Mode load: $count nurses, bucket=$bucket, date=$($LoadDate.ToString('yyyy-MM-dd'))"
            Invoke-AirflowBatch -LoadMode $Mode -NurseCount $count
            Invoke-SnowflakeAndDbt -BucketName $bucket -Bootstrap $isInitial
            if ($RunFivetran)  { Invoke-FivetranSync }
            if ($RunHightouch) { Invoke-HightouchSync }
            Write-Host "[Pipeline] PASS - $Mode pipeline complete."
        }
    }

    if ($Mode -eq "verify") {
        Write-Host "[Verify] Running read-only verification queries..."
        Invoke-Checked {
            python (Join-Path $projectRoot "scripts\run_snowflake_sql.py") `
                --bucket $bucket `
                (Join-Path $projectRoot "snowflake\sql\06_incremental_demo.sql")
        } "Verification query failed"
        Write-Host "[Verify] PASS - verification queries returned results."
    }
}
finally {
    Pop-Location
}