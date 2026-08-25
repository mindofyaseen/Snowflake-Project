[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [string]$PythonExecutable
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $PSScriptRoot "..\.secrets"
}

if ([string]::IsNullOrWhiteSpace($PythonExecutable)) {
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($null -eq $pythonCommand) {
        throw "Python was not found. Pass -PythonExecutable with a Python 3 path containing cryptography."
    }
    $PythonExecutable = $pythonCommand.Source
}

& $PythonExecutable (Join-Path $PSScriptRoot "generate_service_keys.py") `
    --output-directory $OutputDirectory

if ($LASTEXITCODE -ne 0) {
    throw "RSA key generation failed with exit code $LASTEXITCODE."
}
