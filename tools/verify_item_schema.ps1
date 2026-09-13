# SPDX-License-Identifier: MIT

param(
    [string]$SchemaPath = 'C:\Program Files (x86)\Steam\steamapps\common\Team Fortress 2\tf\scripts\items\items_game.txt'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$constantsPath = Join-Path $repoRoot 'src\ubermensch\constants.lua'

if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) {
    throw "TF2 item schema not found: $SchemaPath"
}
if (-not (Test-Path -LiteralPath $constantsPath -PathType Leaf)) {
    throw "Constants module not found: $constantsPath"
}

function Read-LuaMap {
    param(
        [string]$Source,
        [string]$TableName,
        [string]$ValuePattern
    )

    $blockPattern = [regex]::Escape($TableName) + '\s*=\s*\{(?<body>.*?)\r?\n\}'
    $block = [regex]::Match($Source, $blockPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $block.Success) {
        throw "Could not find Lua table $TableName"
    }

    $result = @{}
    $entryPattern = '\[(?<id>\d+)\]\s*=\s*"(?<value>' + $ValuePattern + ')"'
    foreach ($match in [regex]::Matches($block.Groups['body'].Value, $entryPattern)) {
        $result[[int]$match.Groups['id'].Value] = $match.Groups['value'].Value
    }
    return $result
}

$luaSource = Get-Content -Raw -LiteralPath $constantsPath
$actualFamilies = Read-LuaMap -Source $luaSource -TableName 'Constants.ITEM_FAMILY' -ValuePattern 'STOCK|KRITZ'
$actualUnsupported = Read-LuaMap -Source $luaSource -TableName 'Constants.KNOWN_UNSUPPORTED' -ValuePattern 'QUICK-FIX|VACCINATOR'

$records = [System.Collections.Generic.List[object]]::new()
$current = $null
$inItems = $false
foreach ($line in Get-Content -LiteralPath $SchemaPath) {
    if ($line -eq "`t`"items`"") {
        $inItems = $true
        continue
    }
    if ($inItems -and $line -eq "`t`"attributes`"") {
        break
    }
    if (-not $inItems) {
        continue
    }

    if ($line -match '^\t\t"(-?\d+)"\s*$') {
        if ($null -ne $current) {
            $records.Add([pscustomobject]$current)
        }
        $current = [ordered]@{
            Id = [int]$Matches[1]
            Name = ''
            Prefab = ''
            ItemClass = ''
        }
        continue
    }

    if ($null -ne $current -and $line -match '^\t\t\t"([^"]+)"\s+"([^"]*)"\s*(?://.*)?$') {
        $key = $Matches[1]
        $value = $Matches[2]
        if ($key -eq 'name') {
            $current.Name = $value
        } elseif ($key -eq 'prefab') {
            $current.Prefab = $value
        } elseif ($key -eq 'item_class') {
            $current.ItemClass = $value
        }
    }
}
if ($null -ne $current) {
    $records.Add([pscustomobject]$current)
}

$expectedFamilies = @{}
$expectedUnsupported = @{}
$unclassifiedMediguns = [System.Collections.Generic.List[object]]::new()
foreach ($record in $records) {
    $prefabs = @($record.Prefab -split '\s+' | Where-Object { $_ -ne '' })
    if ($prefabs -contains 'weapon_kritzkrieg') {
        $expectedFamilies[$record.Id] = 'KRITZ'
    } elseif ($prefabs -contains 'weapon_medigun' -or $prefabs -contains 'paintkit_weapon_medigun') {
        $expectedFamilies[$record.Id] = 'STOCK'
    } elseif ($record.ItemClass -eq 'tf_weapon_medigun') {
        if ($record.Name -eq 'The Quick-Fix') {
            $expectedUnsupported[$record.Id] = 'QUICK-FIX'
        } elseif ($record.Name -eq 'The Vaccinator') {
            $expectedUnsupported[$record.Id] = 'VACCINATOR'
        } else {
            $unclassifiedMediguns.Add($record)
        }
    }
}

$problems = [System.Collections.Generic.List[string]]::new()
foreach ($id in $expectedFamilies.Keys) {
    if (-not $actualFamilies.ContainsKey($id)) {
        $problems.Add("missing supported definition $id ($($expectedFamilies[$id]))")
    } elseif ($actualFamilies[$id] -ne $expectedFamilies[$id]) {
        $problems.Add("definition $id is $($actualFamilies[$id]); schema requires $($expectedFamilies[$id])")
    }
}
foreach ($id in $actualFamilies.Keys) {
    if (-not $expectedFamilies.ContainsKey($id)) {
        $problems.Add("runtime has extra supported definition $id ($($actualFamilies[$id]))")
    }
}
foreach ($id in $expectedUnsupported.Keys) {
    if (-not $actualUnsupported.ContainsKey($id)) {
        $problems.Add("missing known unsupported definition $id ($($expectedUnsupported[$id]))")
    } elseif ($actualUnsupported[$id] -ne $expectedUnsupported[$id]) {
        $problems.Add("unsupported definition $id has wrong label $($actualUnsupported[$id])")
    }
}
foreach ($id in $actualUnsupported.Keys) {
    if (-not $expectedUnsupported.ContainsKey($id)) {
        $problems.Add("runtime has extra known unsupported definition $id ($($actualUnsupported[$id]))")
    }
}
foreach ($record in $unclassifiedMediguns) {
    $problems.Add("schema has an unreviewed direct medigun definition $($record.Id) ($($record.Name))")
}

$schema = Get-Item -LiteralPath $SchemaPath
$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $SchemaPath
Write-Output "Schema: $($schema.FullName)"
Write-Output "LastWriteUtc: $($schema.LastWriteTimeUtc.ToString('o'))"
Write-Output "SHA256: $($hash.Hash)"
Write-Output "Parsed item definitions: $($records.Count)"
Write-Output "Supported definitions: $($actualFamilies.Count)"
Write-Output "Known unsupported definitions: $($actualUnsupported.Count)"

if ($problems.Count -gt 0) {
    foreach ($problem in $problems) {
        Write-Error $problem
    }
    exit 1
}

Write-Output 'PASS: runtime weapon maps match the installed TF2 item schema.'
