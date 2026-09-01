<#
.SYNOPSIS
M1a: converts PuTTY's saved registry sessions into a Windows Terminal
fragment (profiles + color schemes). Never touches settings.json.

.PARAMETER WhatIf
Print the fragment JSON instead of writing it.

.EXAMPLE
.\Convert-PuttyToTerminal.ps1 -WhatIf
.\Convert-PuttyToTerminal.ps1
#>
[CmdletBinding()]
param(
    [switch]$WhatIf
)

$here = $PSScriptRoot
Import-Module (Join-Path $here 'modules\PuttyRegistry.psm1') -Force
Import-Module (Join-Path $here 'modules\ColorScheme.psm1') -Force
Import-Module (Join-Path $here 'modules\MtPuttyStore.psm1') -Force
Import-Module (Join-Path $here 'modules\FragmentWriter.psm1') -Force
Import-Module (Join-Path $here 'modules\Guid.psm1') -Force

$sessions = Get-PuttySessions
if (-not $sessions -or $sessions.Count -eq 0) {
    Write-Warning "No PuTTY sessions found. Nothing to convert."
    return
}

# Informational only in M1a — logs whether MTPuTTY data exists so we
# know M1b has something real to build against.
Get-MtPuttyGroups | Out-Null

$profiles = @()
$schemes  = @()

foreach ($s in $sessions) {
    if (-not $s.HostName) {
        Write-Verbose "Skipping '$($s.Name)' -- no HostName (likely 'Default Settings' or a template entry)."
        continue
    }

    $schemeName = "PuTTY - $($s.Name)"
    $schemes += ConvertTo-WTColorScheme -SchemeName $schemeName -Colours $s.Colours

    $sshArgs = @()
    if ($s.PortNumber -and $s.PortNumber -ne 22) { $sshArgs += "-p $($s.PortNumber)" }
    $target = if ($s.Username) { "$($s.Username)@$($s.HostName)" } else { $s.HostName }
    $commandLine = "ssh.exe $($sshArgs -join ' ') $target".Trim() -replace '\s+', ' '

    $guid = New-DeterministicGuid -Name "scoot-win-term/putty/$($s.Name)"

    $profiles += [PSCustomObject]@{
        guid        = "{$guid}"
        name        = $s.Name
        commandline = $commandLine
        tabTitle    = $s.Name
        colorScheme = $schemeName
        icon        = 'ms-appx:///ProfileIcons/{9acb9455-ca41-5af7-950f-6bca1bc9722f}.png'
    }
}

if ($profiles.Count -eq 0) {
    Write-Warning "No usable PuTTY sessions (all missing a HostName). Nothing to write."
    return
}

$result = Write-TerminalFragment -Profiles $profiles -Schemes $schemes -WhatIf:$WhatIf

if ($WhatIf) {
    Write-Host "`n(-WhatIf: nothing written)" -ForegroundColor Yellow
} else {
    Write-Host "Wrote $($profiles.Count) profile(s) and $($schemes.Count) scheme(s) to:`n$result" -ForegroundColor Green
    Write-Host "Open Windows Terminal's profile dropdown to check whether it picked these up without a restart." -ForegroundColor Yellow
}
