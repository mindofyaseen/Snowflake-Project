[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$ConnectorId,

    [ValidateSet("1", "5", "15", "30", "60", "120", "180", "360", "480", "720", "1440")]
    [string]$SyncFrequency = "360",

    [switch]$Paused,

    [switch]$PlanOnly
)

$ErrorActionPreference = "Stop"

if (-not $env:FIVETRAN_APIKEY -or -not $env:FIVETRAN_APISECRET) {
    throw "Set FIVETRAN_APIKEY and FIVETRAN_APISECRET in this PowerShell process first."
}

$stackPath = Join-Path $PSScriptRoot "..\infra\terraform\fivetran-schedule"
$stackPath = (Resolve-Path $stackPath).Path

terraform -chdir=$stackPath init
if ($LASTEXITCODE -ne 0) { throw "terraform init failed" }

$arguments = @(
    "-chdir=$stackPath"
    "plan"
    "-var=connector_id=$ConnectorId"
    "-var=sync_frequency=$SyncFrequency"
    "-var=paused=$($Paused.IsPresent.ToString().ToLowerInvariant())"
    "-var=pause_after_trial=true"
    "-out=fivetran.tfplan"
)

terraform @arguments
if ($LASTEXITCODE -ne 0) { throw "terraform plan failed" }

if (-not $PlanOnly -and $PSCmdlet.ShouldProcess($ConnectorId, "Apply the Fivetran connector schedule")) {
    terraform -chdir=$stackPath apply fivetran.tfplan
    if ($LASTEXITCODE -ne 0) { throw "terraform apply failed" }
}
