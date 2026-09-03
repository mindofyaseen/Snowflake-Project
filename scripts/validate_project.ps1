<#
.SYNOPSIS
    CareMatch Modern Data Stack: Unified Local Validation Runner
.DESCRIPTION
    Runs all credential-free quality, syntax, security, and schema checks.
    Returns exit code 0 if all checks pass, or non-zero on any failure.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Push-Location $projectRoot

$results = [ordered]@{}
$failed = $false

function Run-Step {
    param([string]$Name, [scriptblock]$Action)
    Write-Host "`n>>> Running: $Name..." -ForegroundColor Cyan
    try {
        & $Action
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            throw "Command exited with non-zero status ($LASTEXITCODE)"
        }
        $results[$Name] = "PASS"
        Write-Host "PASS: $Name" -ForegroundColor Green
    } catch {
        $results[$Name] = "FAIL: $_"
        Write-Host "FAIL: $Name - $_" -ForegroundColor Red
        $script:failed = $true
    }
}

try {
    # 1. Python Unit Tests & Data Contracts
    Run-Step "Python Unit Tests & Contracts" {
        python -m unittest discover -s tests -v
    }

    # 2. Credential-Free dbt Project Parse
    Run-Step "Credential-Free dbt Parse" {
        $tmpDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName())
        [System.IO.Directory]::CreateDirectory($tmpDir) | Out-Null
        $dummyProfiles = @"
carematch:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: dummy_account
      user: dummy_user
      password: dummy_password
      role: dummy_role
      database: CAREMATCH
      warehouse: dummy_wh
      schema: ANALYTICS
      threads: 1
"@
        try {
            [System.IO.File]::WriteAllText((Join-Path $tmpDir "profiles.yml"), $dummyProfiles, [System.Text.UTF8Encoding]::new($false))
            dbt --no-version-check --no-send-anonymous-usage-stats parse --project-dir dbt --profiles-dir $tmpDir
        } finally {
            if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
        }
    }

    # 3. Snowflake SQL Dry-Run Parse & Token Check
    Run-Step "Snowflake SQL Dry-Run Validation" {
        python scripts/run_snowflake_sql.py --dry-run --bucket dummy-bucket `
            snowflake/sql/02_s3_stage_and_raw_load.sql `
            snowflake/sql/06_incremental_demo.sql `
            snowflake/sql/07_pipeline_audit.sql
    }

    # 4. PowerShell Syntax Validation
    Run-Step "PowerShell Syntax Validation" {
        $allOk = $true
        Get-ChildItem -Path "scripts" -Filter "*.ps1" | ForEach-Object {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$errors)
            if ($errors.Count -gt 0) {
                $allOk = $false
                Write-Host "Parse error in $($_.Name): $errors"
            }
        }
        if (-not $allOk) { throw "PowerShell script syntax errors detected" }
    }

    # 5. Terraform Formatting & Validation
    Run-Step "Terraform Format Check" {
        terraform fmt -check -recursive infra/terraform
    }

    Run-Step "Terraform Validate (Platform)" {
        terraform -chdir=infra/terraform/platform validate
    }

    # 6. UTF-8 BOM Check
    Run-Step "UTF-8 BOM Scan" {
        python -c "
import pathlib
bom = [str(p) for p in pathlib.Path('.').rglob('*') if p.is_file() and not any(x in str(p) for x in ['.git', '.venv', '__pycache__', '.terraform', 'data']) and p.read_bytes().startswith(b'\xef\xbb\xbf')]
if bom:
    raise RuntimeError(f'Files with UTF-8 BOM found: {bom}')
"
    }

    # 7. Secret & State Leak Scan
    Run-Step "Secret & State Leak Scan" {
        python -c "
import subprocess
tracked = subprocess.check_output(['git', 'ls-files'], text=True).splitlines()
violations = []
for p in tracked:
    if (p.endswith('.env') and not p.endswith('.env.example')) or any(p.endswith(x) for x in ['.p8', '.pem', '.key']) or '.tfstate' in p:
        violations.append((p, 'Forbidden secret or state file'))
if violations:
    raise RuntimeError(f'Tracked file violations found: {violations}')
"
    }

    # 8. Git Whitespace Diff Check
    Run-Step "Git Diff Whitespace Check" {
        git diff --check
    }

    # Summary
    Write-Host "`n==================================================" -ForegroundColor Cyan
    Write-Host " CareMatch Unified Validation Summary" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    foreach ($k in $results.Keys) {
        $status = $results[$k]
        if ($status -eq "PASS") {
            Write-Host "  [PASS] $k" -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] $k ($status)" -ForegroundColor Red
        }
    }
    Write-Host "==================================================" -ForegroundColor Cyan

    if ($failed) {
        Write-Host "`nVALIDATION FAILED: One or more checks failed.`n" -ForegroundColor Red
        exit 1
    } else {
        Write-Host "`nVALIDATION PASSED: All 8 validation checks succeeded!`n" -ForegroundColor Green
        exit 0
    }
} finally {
    Pop-Location
}
