# PuTTY sessions authenticate via Pageant/.ppk, which plain ssh.exe
# doesn't understand. If a session's host already has a matching Host
# alias in ~/.ssh/config, that alias's IdentityFile (an OpenSSH-format
# key the user has separately set up) is what actually lets ssh.exe
# authenticate -- so prefer the alias over a literal user@host target.

function Get-SshConfigHosts {
    [CmdletBinding()]
    param(
        [string]$ConfigPath = (Join-Path $HOME '.ssh\config')
    )

    if (-not (Test-Path $ConfigPath)) { return @() }

    $entries = @()
    $current = $null
    foreach ($line in Get-Content $ConfigPath) {
        $line = $line.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }

        $parts = $line -split '\s+', 2
        $key = $parts[0]
        $value = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' }

        if ($key -ieq 'Host') {
            if ($current) { $entries += [PSCustomObject]$current }
            # Skip wildcard/multi-target Host lines -- not a concrete alias.
            if ($value -match '[\*\?\s]') {
                $current = $null
            } else {
                $current = @{ Alias = $value; HostName = $value; User = $null }
            }
        } elseif ($current) {
            switch -Regex ($key) {
                '^HostName$' { $current.HostName = $value }
                '^User$'     { $current.User = $value }
            }
        }
    }
    if ($current) { $entries += [PSCustomObject]$current }

    return $entries
}

function Resolve-SshTarget {
    <#
    .SYNOPSIS
    Returns the ssh.exe target to use for a PuTTY session: a matching
    ~/.ssh/config Host alias if one exists (by resolved host + user),
    otherwise the literal "user@host" (or bare host).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$HostName,
        [string]$Username,
        [string]$ConfigPath = (Join-Path $HOME '.ssh\config')
    )

    $effectiveHost = $HostName
    $effectiveUser = $Username
    if (-not $effectiveUser -and $effectiveHost -match '^(?<user>[^@]+)@(?<host>.+)$') {
        $effectiveUser = $Matches.user
        $effectiveHost = $Matches.host
    }

    $match = Get-SshConfigHosts -ConfigPath $ConfigPath | Where-Object {
        $_.HostName -and $_.HostName -ieq $effectiveHost -and
        (-not $effectiveUser -or -not $_.User -or $_.User -ieq $effectiveUser)
    } | Select-Object -First 1

    if ($match) { return $match.Alias }
    if ($effectiveUser) { return "$effectiveUser@$effectiveHost" }
    return $effectiveHost
}

Export-ModuleMember -Function Get-SshConfigHosts, Resolve-SshTarget
