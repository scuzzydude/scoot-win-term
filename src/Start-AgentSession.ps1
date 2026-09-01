<#
.SYNOPSIS
Lists every live agent session across all servers in servers.conf and
opens the chosen one in a new Windows Terminal tab, attached.

.PARAMETER ServersConfPath
Passed through to Get-AgentManifest.ps1.
#>
[CmdletBinding()]
param(
    [string]$ServersConfPath = (Join-Path $PSScriptRoot 'servers.conf')
)

. (Join-Path $PSScriptRoot 'Get-AgentManifest.ps1')

$agents = Get-AgentManifest -ServersConfPath $ServersConfPath

if (-not $agents -or $agents.Count -eq 0) {
    Write-Warning "No live agent sessions found across any server."
    return
}

Write-Host ""
for ($i = 0; $i -lt $agents.Count; $i++) {
    $a = $agents[$i]
    $purposeSuffix = if ($a.Purpose) { " - $($a.Purpose)" } else { '' }
    Write-Host ("[{0}] {1} @ {2}{3}" -f $i, $a.Name, $a.Label, $purposeSuffix)
}
Write-Host ""

$choice = Read-Host "Pick an agent to open (number)"
if ($choice -notmatch '^\d+$' -or [int]$choice -ge $agents.Count) {
    Write-Warning "Invalid choice."
    return
}

$a = $agents[[int]$choice]
$tabTitle = "$($a.Name) @ $($a.Host)"
$remoteAttach = $a.AttachCmd -replace '"', '\"'

& wt.exe new-tab --title "$tabTitle" --tabColor "$($a.Color)" -- ssh $a.Host -t "$remoteAttach"
