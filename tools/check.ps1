# SPDX-License-Identifier: MIT

param(
    [string]$LuaCommand = 'lua',
    [string]$LuaCompilerCommand = 'luac',
    [string]$LuacheckCommand = 'luacheck',
    [string]$LDocCommand = 'ldoc',
    [switch]$VerifyItemSchema,
    [string]$SchemaPath = 'C:\Program Files (x86)\Steam\steamapps\common\Team Fortress 2\tf\scripts\items\items_game.txt'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-Executable {
    param(
        [string]$Command,
        [string]$Purpose,
        [string[]]$FallbackCommands = @()
    )

    $candidates = @($Command) + $FallbackCommands
    foreach ($candidate in $candidates) {
        $resolved = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $resolved) {
            return $resolved.Source
        }

        if ([System.IO.Path]::GetDirectoryName($candidate)) {
            continue
        }

        $pathExtensions = if ($env:PATHEXT) {
            @('') + @($env:PATHEXT -split ';')
        } else {
            @('', '.exe', '.cmd', '.bat', '.com')
        }
        $persistedPaths = @(
            [Environment]::GetEnvironmentVariable(
                'Path',
                [EnvironmentVariableTarget]::User
            ),
            [Environment]::GetEnvironmentVariable(
                'Path',
                [EnvironmentVariableTarget]::Machine
            )
        )

        foreach ($persistedPath in $persistedPaths) {
            foreach ($pathEntry in @($persistedPath -split [System.IO.Path]::PathSeparator)) {
                $directory = [Environment]::ExpandEnvironmentVariables(
                    $pathEntry.Trim().Trim('"')
                )
                if (-not $directory) {
                    continue
                }

                foreach ($extension in $pathExtensions) {
                    $path = Join-Path $directory ($candidate + $extension.ToLowerInvariant())
                    if (Test-Path -LiteralPath $path -PathType Leaf) {
                        return (Resolve-Path -LiteralPath $path).Path
                    }
                }
            }
        }
    }

    throw "$Purpose executable not found. Tried: $($candidates -join ', '). Install it or pass its executable path explicitly."
}

function Assert-LastExitCode {
    param([string]$Description)

    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE."
    }
}

$luaFallbackCommands = if ($PSBoundParameters.ContainsKey('LuaCommand')) {
    @()
} else {
    @('lua54', 'lua5.4', 'lua53', 'lua5.3', 'lua52', 'lua5.2', 'lua51', 'lua5.1')
}
$luacFallbackCommands = if ($PSBoundParameters.ContainsKey('LuaCompilerCommand')) {
    @()
} else {
    @('luac54', 'luac5.4', 'luac53', 'luac5.3', 'luac52', 'luac5.2', 'luac51', 'luac5.1')
}
$lua = Resolve-Executable `
    -Command $LuaCommand `
    -Purpose 'Lua interpreter' `
    -FallbackCommands $luaFallbackCommands
$luac = Resolve-Executable `
    -Command $LuaCompilerCommand `
    -Purpose 'Lua compiler' `
    -FallbackCommands $luacFallbackCommands
$luacheck = Resolve-Executable `
    -Command $LuacheckCommand `
    -Purpose 'Luacheck' `
    -FallbackCommands $(if ($PSBoundParameters.ContainsKey('LuacheckCommand')) {
        @()
    } else {
        @(Join-Path $repoRoot '.tools\rocks51\bin\luacheck.bat')
    })
$ldoc = Resolve-Executable `
    -Command $LDocCommand `
    -Purpose 'LDoc' `
    -FallbackCommands $(if ($PSBoundParameters.ContainsKey('LDocCommand')) {
        @()
    } else {
        @(Join-Path $repoRoot '.tools\rocks51\bin\ldoc.bat')
    })
$buildScript = Join-Path $PSScriptRoot 'build_runtime.ps1'
$validationBuildScript = Join-Path $PSScriptRoot 'build_validation_runtime.ps1'
$schemaScript = Join-Path $PSScriptRoot 'verify_item_schema.ps1'

Push-Location -LiteralPath $repoRoot
try {
    Write-Output "==> Lua interpreter: $lua"
    & $lua -v
    Assert-LastExitCode -Description 'Lua version check'

    Write-Output '==> Automated tests'
    & $lua 'tests/run.lua'
    Assert-LastExitCode -Description 'Automated tests'

    Write-Output "==> Lua compiler: $luac"
    & $luac -v
    Assert-LastExitCode -Description 'Lua compiler version check'

    $luaFiles = @(
        Get-Item -LiteralPath 'ubermensch.lua'
        Get-Item -LiteralPath 'ubermensch_validation.lua'
        Get-Item -LiteralPath 'tools\benchmark_hot_path.lua'
        Get-ChildItem -LiteralPath 'src', 'tests' -Filter '*.lua' -File -Recurse
        Get-ChildItem -LiteralPath 'tools\validation' -Filter '*.lua' -File -Recurse
    ) | Sort-Object -Property FullName -Unique

    foreach ($luaFile in $luaFiles) {
        & $luac -p $luaFile.FullName
        Assert-LastExitCode -Description "Syntax check for $($luaFile.FullName)"
    }
    Write-Output "PASS: syntax valid for $($luaFiles.Count) Lua files."

    Write-Output "==> Luacheck: $luacheck"
    & $luacheck '--codes' '--ranges' '--no-color' `
        'src' 'tests' 'tools/validation' 'tools/benchmark_hot_path.lua'
    Assert-LastExitCode -Description 'Luacheck static analysis'

    Write-Output "==> LDoc: $ldoc"
    & $ldoc '--fatalwarnings' '--testing' '.'
    Assert-LastExitCode -Description 'LDoc generation'

    Write-Output '==> Generated runtime'
    & $buildScript -Check
    Assert-LastExitCode -Description 'Generated runtime check'
    & $validationBuildScript -Check
    Assert-LastExitCode -Description 'Generated validation runtime check'

    if ($VerifyItemSchema) {
        Write-Output '==> Installed TF2 item schema'
        & $schemaScript -SchemaPath $SchemaPath
        Assert-LastExitCode -Description 'TF2 item-schema verification'
    } else {
        Write-Output 'SKIP: installed TF2 item schema (pass -VerifyItemSchema to enable).'
    }

    Write-Output 'PASS: all requested automated checks completed.'
} finally {
    Pop-Location
}
