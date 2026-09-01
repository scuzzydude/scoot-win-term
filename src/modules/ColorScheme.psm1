Import-Module (Join-Path $PSScriptRoot 'Guid.psm1') -Force

# PuTTY's Colour0..Colour21 registry slots, in order. Source: PuTTY's
# own colour config array (config.c / putty.h `Colours`).
$Script:PuttySlot = @{
    Foreground     = 0
    ForegroundBold = 1
    Background     = 2
    BackgroundBold = 3
    CursorText     = 4
    CursorColour   = 5
    Black          = 6;  BlackBold  = 7
    Red            = 8;  RedBold    = 9
    Green          = 10; GreenBold  = 11
    Yellow         = 12; YellowBold = 13
    Blue           = 14; BlueBold   = 15
    Magenta        = 16; MagentaBold = 17
    Cyan           = 18; CyanBold   = 19
    White          = 20; WhiteBold  = 21
}

function ConvertTo-HexColor {
    param([int[]]$Rgb)
    if (-not $Rgb -or $Rgb.Count -lt 3) { return $null }
    '#{0:X2}{1:X2}{2:X2}' -f $Rgb[0], $Rgb[1], $Rgb[2]
}

function ConvertTo-WTColorScheme {
    <#
    .SYNOPSIS
    Builds a Windows Terminal color scheme object from one PuTTY session's
    Colours hashtable (as produced by Get-PuttySessions).

    .NOTES
    PuTTY has no concept of a "selection background" color; Windows
    Terminal requires one. We default it to a fixed, documented value
    rather than guessing one out of PuTTY's palette.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SchemeName,
        [Parameter(Mandatory)][hashtable]$Colours
    )

    $slot = $Script:PuttySlot
    $c = @{}
    foreach ($key in $slot.Keys) {
        $c[$key] = ConvertTo-HexColor $Colours[$slot[$key]]
    }

    [PSCustomObject]@{
        name                = $SchemeName
        foreground          = $c.Foreground
        background          = $c.Background
        cursorColor         = $c.CursorColour
        # No PuTTY equivalent — documented fixed default, not derived.
        selectionBackground = '#264F78'
        black               = $c.Black
        red                 = $c.Red
        green               = $c.Green
        yellow              = $c.Yellow
        blue                = $c.Blue
        purple              = $c.Magenta
        cyan                = $c.Cyan
        white               = $c.White
        brightBlack         = $c.BlackBold
        brightRed           = $c.RedBold
        brightGreen         = $c.GreenBold
        brightYellow        = $c.YellowBold
        brightBlue          = $c.BlueBold
        brightPurple        = $c.MagentaBold
        brightCyan          = $c.CyanBold
        brightWhite         = $c.WhiteBold
    }
}

Export-ModuleMember -Function ConvertTo-WTColorScheme, ConvertTo-HexColor
