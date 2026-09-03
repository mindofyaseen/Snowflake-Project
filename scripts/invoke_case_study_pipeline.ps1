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
  echo "  attempt ${attempt}: DAG state=${state}"
  if [ "`$state" = "success" ]; then exit 0; fi
  if [ "`$state" = "failed" ]; then exit 1; fi
  sleep 15
done
echo 'Timed out waiting for the Airflow DAG run' >&2
exit 1
"@
    $parameters = @{ commands = @($remoteCommand) } | ConvertTo-Json -Compress
    Write-Host "[Airflow] Sending SSM command to instance $instanceId..."
    $commandId = aws ssm send-command --profile $AwsProfile --region $AwsRegion --instance-ids $instanceId --document-name AWS-RunShellScript --parameters $parameters --query Command.CommandId --output text
    if ($LASTEXITCODE -ne 0 -or -not $commandId) { throw "Airflow SSM trigger failed." }
    Write-Host "[Airflow] SSM command ID: $commandId – polling for completion..."
    aws ssm wait command-executed --profile $AwsProfile --region $AwsRegion --command-id $commandId --instance-id $instanceId
    $ssmExitCode = $LASTEXITCODE
    $invocation = aws ssm get-command-invocation --profile $AwsProfile --region $AwsRegion --command-id $commandId --instance-id $instanceId --query "{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}" | ConvertFrom-Json
    Write-Host "[Airflow] SSM status : $($invocation.Status)"
    if ($invocation.Output) { Write-Host "[Airflow] stdout:`n$($invocation.Output)" }
    if ($invocation.Error)  { Write-Host "[Airflow] stderr:`n$($invocation.Error)" }
    if ($ssmExitCode -ne 0 -or $invocation.Status -ne "Success") {
        throw "Airflow trigger command did not complete successfully (status=$($invocation.Status))."
    }
    Write-Host "[Airflow] PASS – DAG run $runId succeeded."
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
    Write-Host "[Snowflake] PASS – raw load complete."

    if (-not $SkipDbt) {
        if (-not (Get-Command dbt -ErrorAction SilentlyContinue)) { throw "dbt is not installed or not on PATH." }
        Invoke-Checked { dbt deps --project-dir (Join-Path $projectRoot "dbt") --profiles-dir (Join-Path $projectRoot "dbt") } "dbt deps failed"
        Invoke-Checked { dbt build --project-dir (Join-Path $projectRoot "dbt") --profiles-dir (Join-Path $projectRoot "dbt") } "dbt build failed"
        Write-Host "[dbt] PASS – models built and tests passed."
    }
}

function Invoke-FivetranSync {
    # Validate required environment variables before calling the API.
    $missing = @()
    if (-not $env:FIVETRAN_APIKEY)        { $missing += "FIVETRAN_APIKEY" }
    if (-not $env:FIVETRAN_APISECRET)     { $missing += "FIVETRAN_APISECRET" }
    if (-not $env:FIVETRAN_CONNECTOR_ID)  { $missing += "FIVETRAN_CONNECTOR_ID" }
    if ($missing) { throw "Missing Fivetran environment variables: $($missing -join ', '). Set them and retry." }

    $pair  = "$($env:FIVETRAN_APIKEY):$($env:FIVETRAN_APISECRET)"
    $token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
    $headers = @{ Authorization = "Basic $token" }
    $baseUri  = "https://api.fivetran.com/v1/connectors/$($env:FIVETRAN_CONNECTOR_ID)"

    Write-Host "[Fivetran] Triggering force sync for connector $($env:FIVETRAN_CONNECTOR_ID)..."
    try {
        Invoke-RestMethod -Method Post -Uri "$baseUri/force" -Headers $headers | Out-Null
    } catch {
        throw "[Fivetran] Force-sync API call failed: $_"
    }

    # Poll until sync_state leaves the running/scheduled set or the timeout expires.
    $timeoutSeconds = 1800   # 30 minutes
    $sleepSeconds   = 30
    $started        = [datetime]::UtcNow
    $terminalStates = @("connected", "broken", "incomplete", "paused")
    $successStates  = @("connected")

    Write-Host "[Fivetran] Polling sync status (timeout ${timeoutSeconds}s, interval ${sleepSeconds}s)..."
    while (([datetime]::UtcNow - $started).TotalSeconds -lt $timeoutSeconds) {
        Start-Sleep -Seconds $sleepSeconds
        try {
            $response  = Invoke-RestMethod -Method Get -Uri $baseUri -Headers $headers
            $syncState = $response.data.status.sync_state
        } catch {
            Write-Warning "[Fivetran] Status poll failed (will retry): $_"
            continue
        }
        $elapsed = [int]([datetime]::UtcNow - $started).TotalSeconds
        Write-Host "[Fivetran]   +${elapsed}s  sync_state=$syncState"
        if ($syncState -in $terminalStates) {
            if ($syncState -in $successStates) {
                Write-Host "[Fivetran] PASS – sync completed (state=$syncState, elapsed=${elapsed}s)."
                return
            }
            throw "[Fivetran] FAIL – sync ended in non-success state '$syncState' after ${elapsed}s."
        }
    }
    throw "[Fivetran] FAIL – sync did not complete within ${timeoutSeconds}s."
}

function Invoke-HightouchSync {
    # Validate required environment variables before calling the API.
    $missing = @()
    if (-not $env:HIGHTOUCH_API_KEY) { $missing += "HIGHTOUCH_API_KEY" }
    if (-not $env:HIGHTOUCH_SYNC_ID) { $missing += "HIGHTOUCH_SYNC_ID" }
    if ($missing) { throw "Missing Hightouch environment variables: $($missing -join ', '). Set them and retry." }

    $headers = @{ Authorization = "Bearer $($env:HIGHTOUCH_API_KEY)" }
    $syncUri = "https://api.hightouch.com/api/v1/syncs/$($env:HIGHTOUCH_SYNC_ID)"

    Write-Host "[Hightouch] Triggering sync $($env:HIGHTOUCH_SYNC_ID)..."
    try {
        $triggered = Invoke-RestMethod -Method Post -Uri "$syncUri/trigger" -Headers $headers
    } catch {
        throw "[Hightouch] Trigger API call failed: $_"
    }
    $syncRequestId = $triggered.id
    Write-Host "[Hightouch] Sync request ID: $syncRequestId"

    # Poll the sync request list for the launched request.
    $timeoutSeconds = 1800   # 30 minutes
    $sleepSeconds   = 30
    $started        = [datetime]::UtcNow
    $terminalStates = @("success", "failed", "interrupted", "cancelled")

    Write-Host "[Hightouch] Polling sync status (timeout ${timeoutSeconds}s, interval ${sleepSeconds}s)..."
    while (([datetime]::UtcNow - $started).TotalSeconds -lt $timeoutSeconds) {
        Start-Sleep -Seconds $sleepSeconds
        try {
            $requests = Invoke-RestMethod -Method Get -Uri "$syncUri/sync_requests" -Headers $headers
            $latest   = $requests.data | Where-Object { $_.id -eq $syncRequestId } | Select-Object -First 1
            if (-not $latest) { $latest = $requests.data | Select-Object -First 1 }
            $status = $latest.status
        } catch {
            Write-Warning "[Hightouch] Status poll failed (will retry): $_"
            continue
        }
        $elapsed = [int]([datetime]::UtcNow - $started).TotalSeconds
        Write-Host "[Hightouch]   +${elapsed}s  status=$status"
        if ($status -in $terminalStates) {
            if ($status -eq "success") {
                Write-Host "[Hightouch] PASS – sync completed (status=$status, elapsed=${elapsed}s)."
                return
            }
            throw "[Hightouch] FAIL – sync ended in non-success status '$status' after ${elapsed}s."
        }
    }
    throw "[Hightouch] FAIL – sync did not complete within ${timeoutSeconds}s."
}

Push-Location $projectRoot
try {
    if ($Mode -eq "infrastructure") {
        Invoke-Infrastructure
        return
    }

    Write-Host "[Validate] Running local unit tests..."
    Invoke-Checked { python -m unittest discover -s tests -v } "Local validation failed"
    Write-Host "[Validate] PASS – all unit tests passed."

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
            Write-Host "[Pipeline] PASS – $Mode pipeline complete."
        }
    }

    if ($Mode -eq "verify") {
        Write-Host "[Verify] Running read-only verification queries..."
        Invoke-Checked { python (Join-Path $projectRoot "scripts\run_snowflake_sql.py") --bucket $bucket (Join-Path $projectRoot "snowflake\sql\06_incremental_demo.sql") } "Verification query failed"
        Write-Host "[Verify] PASS – verification queries returned results."
    }
}
finally {
    Pop-Location
}

