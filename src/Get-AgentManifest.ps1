<#
.SYNOPSIS
Aggregates the live agent manifest across every server in servers.conf.
One SSH round-trip per server; reads that server's manifest.jsonl and
cross-checks it against a live `screen -ls` in the same round-trip so
stale (no-longer-running) entries are dropped before they ever reach
the caller.

.PARAMETER ServersConfPath
Path to the pipe-delimited server registry. Defaults to servers.conf
next to this script.

.OUTPUTS
PSCustomObject per live agent: Host, Label, Color, Name, Purpose, Cwd,
AttachCmd, StartTime.
#>
[CmdletBinding()]
param(
    [string]$ServersConfPath
)
if (-not $ServersConfPath) { $ServersConfPath = Join-Path $PSScriptRoot 'servers.conf' }

function Read-ServerRegistry {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path)) {
        throw "Server registry not found: $Path"
    }

    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith('#')) { return }
        $parts = $line -split '\|'
        [PSCustomObject]@{
            HostName = $parts[0]
            Label    = if ($parts.Count -gt 1) { $parts[1] } else { $parts[0] }
            Color    = if ($parts.Count -gt 2) { $parts[2] } else { '#888888' }
        }
    }
}

function Get-ServerAgentManifest {
    param(
        [Parameter(Mandatory)][string]$HostName,
        [string]$Label = $HostName,
        [string]$Color = '#888888'
    )

    $remoteCmd = 'cat ~/.scoot-term/manifest.jsonl 2>/dev/null; echo ---LIVE---; screen -ls 2>/dev/null'
    $raw = & ssh -o BatchMode=yes -o ConnectTimeout=5 $HostName $remoteCmd 2>$null

    if (-not $raw) {
        Write-Warning "No response from '$HostName' (unreachable, or manifest/screen empty)."
        return @()
    }

    $text = $raw -join "`n"
    $sections = $text -split '---LIVE---'
    $manifestText = $sections[0]
    $liveText = if ($sections.Count -gt 1) { $sections[1] } else { '' }

    $liveIds = [regex]::Matches($liveText, '(?m)^\s*(\d+\.\S+)') |
        ForEach-Object { $_.Groups[1].Value }

    $entries = @()
    foreach ($line in ($manifestText -split "`n")) {
        $line = $line.Trim()
        if (-not $line) { continue }

        try {
            $obj = $line | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Warning "Skipping malformed manifest line from '$HostName'."
            continue
        }

        if ($liveIds -notcontains $obj.backend_id) { continue }

        $entries += [PSCustomObject]@{
            Host      = $HostName
            Label     = $Label
            Color     = $Color
            Name      = $obj.name
            Purpose   = $obj.purpose
            Cwd       = $obj.cwd
            AttachCmd = $obj.attach_cmd
            StartTime = $obj.start_time
        }
    }

    return $entries
}

function Get-AgentManifest {
    [CmdletBinding()]
    param([string]$ServersConfPath)

    if (-not $ServersConfPath) { $ServersConfPath = Join-Path $PSScriptRoot 'servers.conf' }
    $servers = Read-ServerRegistry -Path $ServersConfPath
    $all = @()
    foreach ($s in $servers) {
        $all += Get-ServerAgentManifest -HostName $s.HostName -Label $s.Label -Color $s.Color
    }
    return $all
}

# Only run when invoked directly (not when dot-sourced by another script
# that just wants the functions, e.g. Start-AgentSession.ps1).
if ($MyInvocation.InvocationName -ne '.') {
    Get-AgentManifest -ServersConfPath $ServersConfPath
}
