Import-Module .\modules\PuttyRegistry.psm1 -Force
Import-Module .\modules\ColorScheme.psm1 -Force
Import-Module .\modules\FragmentWriter.psm1 -Force
Import-Module .\modules\Guid.psm1 -Force
$sessions = Get-PuttySessions
$profiles = @(); $schemes = @()
foreach ($s in $sessions) {
    if (-not $s.HostName) { continue }
    $schemeName = "PuTTY - $($s.Name)"
    $schemes += ConvertTo-WTColorScheme -SchemeName $schemeName -Colours $s.Colours
    $sshArgs = @()
    if ($s.PortNumber -and $s.PortNumber -ne 22) { $sshArgs += "-p $($s.PortNumber)" }
    $target = if ($s.Username) { "$($s.Username)@$($s.HostName)" } else { $s.HostName }
    $commandLine = "ssh.exe $($sshArgs -join ' ') $target".Trim() -replace '\s+', ' '
    $guid = New-DeterministicGuid -Name "scoot-win-term/putty/$($s.Name)"
    $profiles += [PSCustomObject]@{ guid = "{$guid}"; name = $s.Name; commandline = $commandLine; tabTitle = $s.Name; colorScheme = $schemeName; icon = 'ms-appx:///ProfileIcons/{9acb9455-ca41-5af7-950f-6bca1bc9722f}.png' }
}
Write-Host "Sessions found: $($sessions.Count)"
$sessions | Select-Object Name, HostName, PortNumber, Username | Format-Table
Write-Host "Profiles built (with HostName): $($profiles.Count)"
Write-TerminalFragment -Profiles $profiles -Schemes $schemes -WhatIf
