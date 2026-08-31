# Reads PuTTY's saved sessions from the Windows registry.
# HKCU:\Software\SimonTatham\PuTTY\Sessions\<UrlEncodedSessionName>

function Get-PuttySessions {
    [CmdletBinding()]
    param()

    $root = 'HKCU:\Software\SimonTatham\PuTTY\Sessions'
    if (-not (Test-Path $root)) {
        Write-Warning "No PuTTY sessions found at $root"
        return @()
    }

    Get-ChildItem -Path $root | ForEach-Object {
        $props = Get-ItemProperty -Path $_.PSPath
        $name = [System.Uri]::UnescapeDataString($_.PSChildName)

        $colours = @{}
        for ($i = 0; $i -le 21; $i++) {
            $val = $props."Colour$i"
            if ($val) {
                $parts = $val -split ',' | ForEach-Object { [int]$_ }
                $colours[$i] = $parts
            }
        }

        [PSCustomObject]@{
            Name           = $name
            HostName       = $props.HostName
            PortNumber     = $props.PortNumber
            Protocol       = if ($props.SSHProtocolVersion -eq 1) { 'ssh1' } else { 'ssh' }
            Username       = $props.UserName
            Colours        = $colours
            # ProxyMethod 6 = "SSH to proxy and use port forwarding" --
            # PuTTY's equivalent of OpenSSH's ProxyJump.
            ProxyMethod    = $props.ProxyMethod
            ProxyHost      = $props.ProxyHost
            ProxyPort      = $props.ProxyPort
            ProxyUsername  = $props.ProxyUsername
        }
    }
}

Export-ModuleMember -Function Get-PuttySessions
