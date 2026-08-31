# Writes a Windows Terminal "fragment" extension file. Fragments are
# auto-detected by Windows Terminal from:
#   %LocalAppData%\Microsoft\Windows Terminal\Fragments\<AppName>\*.json
# This NEVER touches the user's real settings.json.

function Get-FragmentDirectory {
    param([string]$AppName = 'scoot-win-term')
    Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\$AppName"
}

function Write-TerminalFragment {
    <#
    .SYNOPSIS
    Writes/updates one fragment JSON file containing the given profiles
    and color schemes. Re-runs update in place because each profile's
    "guid" is stable/deterministic -- Windows Terminal dedupes fragment
    profiles by guid on its own. Do NOT also set "updates" to a
    profile's own guid: "updates" tells Windows Terminal to patch an
    *existing* profile, and since these guids don't already exist as
    profiles, the loader silently drops the whole entry instead of
    creating it.

    .PARAMETER WhatIf
    Print the JSON that would be written instead of writing it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][array]$Profiles,
        [array]$Schemes = @(),
        [string]$AppName = 'scoot-win-term',
        [string]$FragmentFileName = 'putty-sessions.json',
        [switch]$WhatIf
    )

    $fragment = [ordered]@{
        profiles = $Profiles
        schemes  = $Schemes
    }

    $json = $fragment | ConvertTo-Json -Depth 10

    if ($WhatIf) {
        Write-Output $json
        return
    }

    $dir = Get-FragmentDirectory -AppName $AppName
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $outPath = Join-Path $dir $FragmentFileName

    # Explicit UTF-8 without BOM — PowerShell's default -Encoding utf8
    # adds a BOM on Windows PowerShell 5.1, which Terminal's JSON parser
    # does not tolerate.
    [System.IO.File]::WriteAllText($outPath, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Output $outPath
}

Export-ModuleMember -Function Get-FragmentDirectory, Write-TerminalFragment
