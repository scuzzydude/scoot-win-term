# Deterministic (RFC 4122 v5) GUID generation, so re-running the
# converter produces the *same* profile/scheme GUIDs every time instead
# of creating duplicates in Windows Terminal's fragment merge.

# Fixed namespace for all scoot-win-term-generated GUIDs.
$Script:ScootWinTermNamespace = [guid]'f65ddb7e-706b-4499-8a50-40313caf510a'

function New-DeterministicGuid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [guid]$Namespace = $Script:ScootWinTermNamespace
    )

    $nsBytes = $Namespace.ToByteArray()
    # .NET Guid byte order for the first three fields is little-endian;
    # RFC 4122 wants them big-endian for hashing.
    [Array]::Reverse($nsBytes, 0, 4)
    [Array]::Reverse($nsBytes, 4, 2)
    [Array]::Reverse($nsBytes, 6, 2)

    $nameBytes = [System.Text.Encoding]::UTF8.GetBytes($Name)
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    $hash = $sha1.ComputeHash($nsBytes + $nameBytes)

    $guidBytes = $hash[0..15]
    $guidBytes[6] = ($guidBytes[6] -band 0x0F) -bor 0x50   # version 5
    $guidBytes[8] = ($guidBytes[8] -band 0x3F) -bor 0x80   # variant

    # Flip back to .NET's little-endian layout for the first three fields.
    [Array]::Reverse($guidBytes, 0, 4)
    [Array]::Reverse($guidBytes, 4, 2)
    [Array]::Reverse($guidBytes, 6, 2)

    [guid]::new([byte[]]$guidBytes)
}

Export-ModuleMember -Function New-DeterministicGuid
