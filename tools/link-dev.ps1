# Links this repo's FrogCam folder into the game's UE4SS Mods folder (a directory junction, no admin
# rights needed), so edits in the repo are what the game loads. Also registers the mod in mods.txt / mods.json.
#   powershell -ExecutionPolicy Bypass -File tools\link-dev.ps1 -GameDir "F:\SteamLibrary\steamapps\common\Entropy Survivors"
param(
    [string]$GameDir = "F:\SteamLibrary\steamapps\common\Entropy Survivors"
)
$ErrorActionPreference = "Stop"
$repoMod = Join-Path $PSScriptRoot "..\FrogCam" | Resolve-Path
$mods = Join-Path $GameDir "EntropySurvivors\Binaries\Win64\ue4ss\Mods"
if (-not (Test-Path $mods)) { throw "UE4SS Mods folder not found: $mods (install UE4SS first)" }

$link = Join-Path $mods "FrogCam"
if (Test-Path $link) {
    $item = Get-Item $link -Force
    if ($item.LinkType -eq "Junction") { Write-Host "Junction already exists: $link -> $($item.Target)" }
    else { throw "$link exists and is a real folder; move it away first" }
} else {
    New-Item -ItemType Junction -Path $link -Target $repoMod | Out-Null
    Write-Host "Linked $link -> $repoMod"
}

# mods.txt: add the entry above the Keybinds line
$txt = Join-Path $mods "mods.txt"
if (Test-Path $txt) {
    $lines = Get-Content $txt
    if (-not ($lines -match '^\s*FrogCam\s*:')) {
        $out = @(); $done = $false
        foreach ($l in $lines) {
            if (-not $done -and $l -match '^\s*; Built-in keybinds') { $out += "FrogCam : 1"; $done = $true }
            $out += $l
        }
        if (-not $done) { $out += "FrogCam : 1" }
        [System.IO.File]::WriteAllLines($txt, [string[]]$out, (New-Object System.Text.UTF8Encoding $false))
        Write-Host "Added FrogCam to mods.txt"
    }
}

# mods.json: same entry, before Keybinds
$json = Join-Path $mods "mods.json"
if (Test-Path $json) {
    # (Windows PowerShell 5.1 hands a JSON array over as ONE object: enumerate it into the list)
    $list = New-Object System.Collections.ArrayList
    foreach ($e in (Get-Content $json -Raw | ConvertFrom-Json)) { [void]$list.Add($e) }
    if (-not ($list | Where-Object { $_.mod_name -eq "FrogCam" })) {
        $entry = [pscustomobject]@{ mod_name = "FrogCam"; mod_enabled = $true }
        $kb = -1; for ($i = 0; $i -lt $list.Count; $i++) { if ($list[$i].mod_name -eq "Keybinds") { $kb = $i } }
        if ($kb -ge 0) { $list.Insert($kb, $entry) } else { [void]$list.Add($entry) }
        [System.IO.File]::WriteAllText($json, (ConvertTo-Json -InputObject ([object[]]$list.ToArray()) -Depth 3), (New-Object System.Text.UTF8Encoding $false))
        Write-Host "Added FrogCam to mods.json"
    }
}
