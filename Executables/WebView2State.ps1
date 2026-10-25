function Get-WebView2Executables {
    param([string[]]$Roots)
    if (-not $PSBoundParameters.ContainsKey('Roots')) {
        $Roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432, $env:LOCALAPPDATA)
        $profiles = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -ErrorAction SilentlyContinue
        foreach ($profile in $profiles) {
            try {
                $path = (Get-ItemProperty -LiteralPath $profile.PSPath -ErrorAction Stop).ProfileImagePath
                if ($path) { $Roots += Join-Path ([Environment]::ExpandEnvironmentVariables($path)) 'AppData\Local' }
            } catch {
                Write-Verbose "Skipping unreadable profile entry $($profile.PSChildName): $($_.Exception.Message)"
            }
        }
    }
    foreach ($root in ($Roots | Where-Object { $_ } | Select-Object -Unique)) {
        try {
            $application = Join-Path $root 'Microsoft\EdgeWebView\Application'
            if (-not (Test-Path -LiteralPath $application -ErrorAction Stop)) { continue }
            foreach ($version in (Get-ChildItem -LiteralPath $application -Directory -ErrorAction Stop)) {
                $executable = Join-Path $version.FullName 'msedgewebview2.exe'
                if (Test-Path -LiteralPath $executable -PathType Leaf -ErrorAction Stop) { $executable }
            }
        } catch {
            Write-Verbose "Skipping unreadable WebView2 root ${root}: $($_.Exception.Message)"
        }
    }
}

function Write-WebView2State {
    $guid = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    try {
        $files = @(Get-WebView2Executables)
        Write-Log "WebView2 runtime executables found=$($files.Count)"
        foreach ($file in $files) { Write-Log "WebView2 executable: $file" }
        foreach ($path in @(
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$guid",
            "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$guid"
        )) {
            $version = (Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue).pv
            Write-Log "WebView2 registration: $path; pv=$version"
        }
        $policy = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' -ErrorAction SilentlyContinue
        Write-Log "WebView2 policies: Install=$($policy.('Install' + $guid)); Update=$($policy.('Update' + $guid))"
        if ($files.Count -gt 0) { return $true }
        return $false
    } catch {
        Write-Log "WebView2 final state could not be verified: $($_.Exception.Message)"
        return $null
    }
}
