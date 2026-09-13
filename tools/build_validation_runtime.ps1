# SPDX-License-Identifier: MIT

param(
    [string]$OutputPath,
    [switch]$Check,
    [switch]$Deploy,
    [string]$DeployDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$arguments = @{
    Validation = $true
    Check = $Check
    Deploy = $Deploy
}
if ($OutputPath) {
    $arguments.OutputPath = $OutputPath
}
if ($DeployDirectory) {
    $arguments.DeployDirectory = $DeployDirectory
}

& (Join-Path $PSScriptRoot 'build_runtime.ps1') @arguments
