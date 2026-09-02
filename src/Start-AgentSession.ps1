<#
.SYNOPSIS
Lists every live agent session across all servers in servers.conf and
opens the chosen one in a new Windows Terminal tab, attached.

.PARAMETER ServersConfPath
Passed through to Get-AgentManifest.ps1.
#>
[CmdletBinding()]
param(
    [string]$ServersConfPath
)
if (-not $ServersConfPath) { $ServersConfPath = Join-Path $PSScriptRoot 'servers.conf' }

. (Join-Path $PSScriptRoot 'Get-AgentManifest.ps1')

function ConvertTo-RelativeTime {
    param([AllowNull()][Nullable[datetime]]$Time)
    if (-not $Time) { return '-' }
    $span = (Get-Date) - $Time
    if ($span.TotalSeconds -lt 60) { return "$([int]$span.TotalSeconds)s ago" }
    if ($span.TotalMinutes -lt 60) { return "$([int]$span.TotalMinutes)m ago" }
    if ($span.TotalHours -lt 24) { return "$([int]$span.TotalHours)h ago" }
    return "$([int]$span.TotalDays)d ago"
}

$agents = @(Get-AgentManifest -ServersConfPath $ServersConfPath) |
    Sort-Object -Property @{ Expression = { if ($_.LastActivity) { $_.LastActivity } else { [datetime]::MinValue } }; Descending = $true }

if (-not $agents -or $agents.Count -eq 0) {
    Write-Warning "No live agent sessions found across any server."
    return
}

Write-Host ""
for ($i = 0; $i -lt $agents.Count; $i++) {
    $a = $agents[$i]
    $purposeSuffix = if ($a.Purpose) { " - $($a.Purpose)" } else { '' }
    $statusSuffix = if ($a.Status) { " [$($a.Status)]" } else { '' }
    $ago = ConvertTo-RelativeTime $a.LastActivity
    Write-Host ("[{0}] {1} @ {2}{3}{4} ({5})" -f $i, $a.Name, $a.Label, $purposeSuffix, $statusSuffix, $ago)
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
