if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    exit 1
}

$script:ScriptLog = Join-Path $env:ProgramData 'AME\Logs\XOS-Scripts.log'
function Write-ScriptLog([string]$Message) {
    try {
        if (!(Test-Path (Split-Path $script:ScriptLog -Parent))) {
            New-Item -Path (Split-Path $script:ScriptLog -Parent) -ItemType Directory -Force | Out-Null
        }
        ('[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] WidgetsPolicy: ' + $Message) |
            Out-File -FilePath $script:ScriptLog -Append -Encoding utf8
    } catch { }
}

$policyRoot = Join-Path $env:SystemRoot 'System32\GroupPolicy'
$polPath = Join-Path $policyRoot 'Machine\Registry.pol'
$gptPath = Join-Path $policyRoot 'gpt.ini'
$policies = @(
    @{ Key = 'SOFTWARE\Policies\Microsoft\Dsh'; Name = 'AllowNewsAndInterests'; Label = 'Widgets' },
    @{ Key = 'SOFTWARE\Policies\Microsoft\Windows\Windows Feeds'; Name = 'EnableFeeds'; Label = 'News and interests' }
)
$unicode = [Text.Encoding]::Unicode

function Read-PolString([byte[]]$Bytes, [ref]$Pos) {
    $start = $Pos.Value
    while ($Pos.Value + 1 -lt $Bytes.Length -and [BitConverter]::ToUInt16($Bytes, $Pos.Value) -ne 0) { $Pos.Value += 2 }
    if ($Pos.Value + 1 -ge $Bytes.Length) { throw "unterminated string at offset $start" }
    $text = $unicode.GetString($Bytes, $start, $Pos.Value - $start)
    $Pos.Value += 2
    return $text
}

function Skip-PolChar([byte[]]$Bytes, [ref]$Pos, [char]$Expected) {
    if ($Pos.Value + 1 -ge $Bytes.Length -or [BitConverter]::ToUInt16($Bytes, $Pos.Value) -ne [int]$Expected) {
        throw "expected '$Expected' at offset $($Pos.Value)"
    }
    $Pos.Value += 2
}

function Read-PolEntries([byte[]]$Bytes) {
    $entries = New-Object System.Collections.ArrayList
    if ($Bytes.Length -lt 8 -or [BitConverter]::ToUInt32($Bytes, 0) -ne 0x67655250 -or [BitConverter]::ToUInt32($Bytes, 4) -ne 1) {
        throw 'the file has no PReg version 1 header'
    }
    $pos = 8
    while ($pos -lt $Bytes.Length) {
        $start = $pos
        Skip-PolChar $Bytes ([ref]$pos) '['
        $key = Read-PolString $Bytes ([ref]$pos)
        Skip-PolChar $Bytes ([ref]$pos) ';'
        $name = Read-PolString $Bytes ([ref]$pos)
        Skip-PolChar $Bytes ([ref]$pos) ';'
        if ($pos + 4 -gt $Bytes.Length) { throw "truncated entry at offset $start" }
        $pos += 4
        Skip-PolChar $Bytes ([ref]$pos) ';'
        if ($pos + 4 -gt $Bytes.Length) { throw "truncated entry at offset $start" }
        $size = [BitConverter]::ToUInt32($Bytes, $pos)
        $pos += 4
        Skip-PolChar $Bytes ([ref]$pos) ';'
        if ($pos + $size -gt $Bytes.Length) { throw "truncated entry at offset $start" }
        $pos += $size
        Skip-PolChar $Bytes ([ref]$pos) ']'
        $raw = New-Object byte[] ($pos - $start)
        [Array]::Copy($Bytes, $start, $raw, 0, $raw.Length)
        $null = $entries.Add(@{ Key = $key; Name = $name; Raw = $raw })
    }
    return ,$entries
}

function New-PolDwordEntry([string]$Key, [string]$Name, [uint32]$Value) {
    $stream = New-Object IO.MemoryStream
    foreach ($part in @(
        $unicode.GetBytes('[' + $Key + [char]0 + ';' + $Name + [char]0 + ';'),
        [BitConverter]::GetBytes([uint32]4),
        $unicode.GetBytes(';'),
        [BitConverter]::GetBytes([uint32]4),
        $unicode.GetBytes(';'),
        [BitConverter]::GetBytes($Value),
        $unicode.GetBytes(']'))) {
        $stream.Write($part, 0, $part.Length)
    }
    return ,$stream.ToArray()
}

function Get-GptIniBytes {
    $cse = '{35378EAC-683F-11D2-A89A-00C04FBBCFA2}'
    $tool = '{D02B1F72-3407-48AE-BA88-E8213C6761F1}'
    $lines = New-Object System.Collections.ArrayList
    if (Test-Path -LiteralPath $gptPath) { foreach ($l in [IO.File]::ReadAllLines($gptPath)) { $null = $lines.Add($l) } }
    if (-not ($lines | Where-Object { $_ -match '^\s*\[General\]\s*$' })) { $lines.Insert(0, '[General]') }
    $generalAt = 0
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*\[General\]\s*$') { $generalAt = $i; break } }

    $versionAt = -1; $extAt = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*Version\s*=') { $versionAt = $i }
        elseif ($lines[$i] -match '^\s*gPCMachineExtensionNames\s*=') { $extAt = $i }
    }

    $version = [int64]0
    if ($versionAt -ge 0) { $null = [int64]::TryParse(($lines[$versionAt] -replace '^\s*Version\s*=\s*', '').Trim(), [ref]$version) }
    $machine = (($version -band 0xFFFF) + 1) -band 0xFFFF
    if ($machine -eq 0) { $machine = 1 }
    $newVersion = 'Version=' + (($version -band [int64]4294901760) -bor $machine)
    if ($versionAt -ge 0) { $lines[$versionAt] = $newVersion } else { $lines.Insert($generalAt + 1, $newVersion) }

    $groups = New-Object System.Collections.ArrayList
    if ($extAt -ge 0) {
        foreach ($m in [regex]::Matches(($lines[$extAt] -replace '^\s*gPCMachineExtensionNames\s*=', ''), '\[[^\]]*\]')) { $null = $groups.Add($m.Value) }
    }
    $found = $false
    for ($i = 0; $i -lt $groups.Count; $i++) {
        $guids = @([regex]::Matches($groups[$i], '\{[^}]*\}') | ForEach-Object { $_.Value })
        if ($guids.Count -gt 0 -and $guids[0] -ieq $cse) {
            $found = $true
            if (-not ($guids | Where-Object { $_ -ieq $tool })) {
                $tools = @($guids | Select-Object -Skip 1) + $tool | Sort-Object
                $groups[$i] = '[' + $cse + ($tools -join '') + ']'
            }
        }
    }
    if (-not $found) { $null = $groups.Add('[' + $cse + $tool + ']') }
    $extLine = 'gPCMachineExtensionNames=' + (($groups | Sort-Object) -join '')
    if ($extAt -ge 0) { $lines[$extAt] = $extLine } else { $lines.Insert($generalAt + 1, $extLine) }

    return ,[Text.Encoding]::ASCII.GetBytes((([string[]]$lines) -join "`r`n") + "`r`n")
}

function Write-FileReplace([string]$Path, [byte[]]$Bytes) {
    $temp = $Path + '.xos-tmp'
    try {
        [IO.File]::WriteAllBytes($temp, $Bytes)
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temp, $Path, [NullString]::Value) } else { [IO.File]::Move($temp, $Path) }
    } catch {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Test-PolEntry($Policy) {
    try {
        $expected = [Convert]::ToBase64String((New-PolDwordEntry $Policy.Key $Policy.Name 0))
        foreach ($entry in (Read-PolEntries ([IO.File]::ReadAllBytes($polPath)))) {
            if ($entry.Key -ieq $Policy.Key -and $entry.Name -ieq $Policy.Name -and [Convert]::ToBase64String($entry.Raw) -eq $expected) { return $true }
        }
    } catch { }
    return $false
}

$edition = ''
try { $edition = [string](Get-ItemPropertyValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'EditionID' -ErrorAction Stop) } catch { }
$homeNote = ''
if ($edition -like 'Core*') { $homeNote = "; this is Windows Home ($edition), where Microsoft does not document local Group Policy processing" }

$label = 'SKIPPED Widgets and News policies: '
try {
    $entries = New-Object System.Collections.ArrayList
    if (Test-Path -LiteralPath $polPath) {
        $entries = Read-PolEntries ([IO.File]::ReadAllBytes($polPath))
    } else {
        $null = New-Item -Path (Split-Path $polPath -Parent) -ItemType Directory -Force
    }

    $kept = New-Object System.Collections.ArrayList
    foreach ($entry in $entries) {
        $owned = $false
        foreach ($p in $policies) {
            if ($entry.Key -ieq $p.Key -and ($entry.Name -ieq $p.Name -or $entry.Name -ieq ('**del.' + $p.Name))) { $owned = $true }
        }
        if (-not $owned) { $null = $kept.Add($entry.Raw) }
    }
    foreach ($p in $policies) { $null = $kept.Add((New-PolDwordEntry $p.Key $p.Name 0)) }

    $out = New-Object IO.MemoryStream
    $header = [BitConverter]::GetBytes([uint32]0x67655250) + [BitConverter]::GetBytes([uint32]1)
    $out.Write([byte[]]$header, 0, 8)
    foreach ($raw in $kept) { $out.Write($raw, 0, $raw.Length) }
    $polBytes = $out.ToArray()
    $gptBytes = Get-GptIniBytes
} catch {
    Write-ScriptLog ($label + 'Registry.pol and gpt.ini left unchanged, ' + $_.Exception.Message + $homeNote)
    exit 0
}

try { Write-FileReplace $gptPath $gptBytes } catch {
    Write-ScriptLog ($label + 'gpt.ini could not be written (' + $_.Exception.Message + '), Registry.pol left unchanged' + $homeNote)
    exit 0
}
try { Write-FileReplace $polPath $polBytes } catch {
    Write-ScriptLog ($label + 'Registry.pol could not be written (' + $_.Exception.Message + '), left unchanged; gpt.ini already has the raised version, which changes no setting' + $homeNote)
    exit 0
}

$gpOutput = 'N' | & (Join-Path $env:SystemRoot 'System32\gpupdate.exe') /target:computer /force 2>&1
$gpExit = $LASTEXITCODE
$gpLast = ($gpOutput | Where-Object { "$_".Trim() } | Select-Object -Last 1)

foreach ($p in $policies) {
    $value = $null
    try { $value = Get-ItemPropertyValue -LiteralPath ('HKLM:\' + $p.Key) -Name $p.Name -ErrorAction Stop } catch { }
    $inPol = Test-PolEntry $p
    $name = $p.Label + ' policy: HKLM\' + $p.Key + ' ' + $p.Name
    if ($gpExit -eq 0 -and $inPol -and $null -ne $value -and [int]$value -eq 0) {
        Write-ScriptLog ('OK ' + $name + ' = 0 through local Group Policy')
        continue
    }
    $reasons = @()
    if ($gpExit -ne 0) { $reasons += "gpupdate exit $gpExit ($gpLast)" }
    if (-not $inPol) { $reasons += 'the Registry.pol entry is missing' }
    if ($null -eq $value -or [int]$value -ne 0) { $reasons += 'the value is not 0' }
    Write-ScriptLog ('SKIPPED ' + $name + ': ' + ($reasons -join ', ') + $homeNote)
}
