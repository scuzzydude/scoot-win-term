# MTPuTTY's session/grouping/color store — format NOT YET CONFIRMED.
# This module is intentionally defensive: it only detects *where*
# MTPuTTY's data might live and reports back, so M1a (flat PuTTY import)
# never blocks on it. Real parsing lands in M1b once the actual file/
# registry layout has been confirmed against a real machine.

function Get-MtPuttyConfigPath {
    [CmdletBinding()]
    param()

    $candidates = @(
        (Join-Path $env:APPDATA 'TTYPlus\MTPuTTY\Sessions.xml'),
        (Join-Path $env:APPDATA 'MTPuTTY\Sessions.xml'),
        (Join-Path $env:APPDATA 'TTYPlus\MTPuTTY'),
        (Join-Path $env:APPDATA 'MTPuTTY')
    )

    foreach ($path in $candidates) {
        if (Test-Path $path) { return $path }
    }

    if (Test-Path 'HKCU:\Software\TTYPlus\MTPuTTY') {
        return 'HKCU:\Software\TTYPlus\MTPuTTY'
    }

    return $null
}

function Get-MtPuttyGroups {
    <#
    .SYNOPSIS
    Returns MTPuTTY group/color data, or an empty array with a warning
    if the format hasn't been confirmed/implemented yet.
    #>
    [CmdletBinding()]
    param()

    $path = Get-MtPuttyConfigPath
    if (-not $path) {
        Write-Warning "MTPuTTY config not found in known locations -- skipping grouping/color import (M1a: flat PuTTY sessions only)."
        return @()
    }

    Write-Warning "Found MTPuTTY data at '$path' but parsing isn't implemented yet (M1b). Run the diagnostic dump and share it so this can be built against the real format."
    return @()
}

Export-ModuleMember -Function Get-MtPuttyConfigPath, Get-MtPuttyGroups
