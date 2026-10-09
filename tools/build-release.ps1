# Builds the two release zips into dist\:
#   FrogCam-v<version>-with-UE4SS.zip   extract into EntropySurvivors\Binaries\Win64 - UE4SS + FrogCam, set up
#   FrogCam-v<version>-mod-only.zip     just the FrogCam folder, for people who already run UE4SS
# The version comes from FrogCam\Scripts\main.lua. The UE4SS build is the one FrogCam was tested with; it is
# kept in third_party\ (not in git) and downloaded there when missing.
#   powershell -ExecutionPolicy Bypass -File tools\build-release.ps1
param(
    [string]$UE4SSName = "UE4SS_v3.0.1-1161-g6eb3d9bc",
    [string]$UE4SSUrl = "https://github.com/UE4SS-RE/RE-UE4SS/releases/download/experimental-latest/UE4SS_v3.0.1-1161-g6eb3d9bc.zip"
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$utf8 = New-Object System.Text.UTF8Encoding $false

$version = ([regex]::Match((Get-Content "$root\FrogCam\Scripts\main.lua" -Raw), 'A\.version = "([^"]+)"')).Groups[1].Value
if (-not $version) { throw "version not found in main.lua" }
Write-Host "FrogCam v$version"

# UE4SS: the tested build (the experimental-latest download is replaced by newer builds over time)
$ue4ssZip = "$root\third_party\$UE4SSName.zip"
if (-not (Test-Path $ue4ssZip)) {
    New-Item -ItemType Directory -Force "$root\third_party" | Out-Null
    Write-Host "Downloading $UE4SSUrl"
    Invoke-WebRequest -Uri $UE4SSUrl -OutFile $ue4ssZip -UseBasicParsing
}

$dist = "$root\dist"
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory $dist | Out-Null

function Copy-Mod($dest) {
    # the mod folder without the files it writes at runtime
    robocopy "$root\FrogCam" $dest /E /XF *.log *.cfg /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "copying FrogCam failed ($LASTEXITCODE)" }
}
function Write-Instructions($template, $dest) {
    $text = (Get-Content "$root\release\$template" -Raw).Replace("{VERSION}", "v$version").Replace("{UE4SS}", $UE4SSName)
    [System.IO.File]::WriteAllText("$dest\FrogCam - HOW TO INSTALL.txt", $text.Replace("`r`n", "`n").Replace("`n", "`r`n"), $utf8)
}

# ---- mod only
$modOnly = "$dist\mod-only"
Copy-Mod "$modOnly\FrogCam"
Write-Instructions "INSTALL-mod-only.txt" $modOnly

# ---- with UE4SS: the UE4SS zip as released, plus FrogCam, with the mod list set up
$full = "$dist\with-ue4ss"
[System.IO.Compression.ZipFile]::ExtractToDirectory($ue4ssZip, $full)
$mods = "$full\ue4ss\Mods"
if (-not (Test-Path $mods)) { throw "unexpected UE4SS layout: $mods missing" }
Copy-Mod "$mods\FrogCam"
Write-Instructions "INSTALL-full.txt" $full

# mods.txt: Blueprint mod loader off (not needed, and kept off while testing), FrogCam on above Keybinds
$out = @()
foreach ($l in (Get-Content "$mods\mods.txt")) {
    if ($l -match '^\s*(BPModLoaderMod|BPML_GenericFunctions)\s*:') { $l = ($l -replace ':\s*\d', ': 0') }
    if ($l -match '^\s*; Built-in keybinds') { $out += "FrogCam : 1" }
    $out += $l
}
[System.IO.File]::WriteAllLines("$mods\mods.txt", [string[]]$out, $utf8)

# mods.json: the same (Windows PowerShell 5.1 hands a JSON array over as ONE object: enumerate it)
if (Test-Path "$mods\mods.json") {
    $list = New-Object System.Collections.ArrayList
    foreach ($e in (Get-Content "$mods\mods.json" -Raw | ConvertFrom-Json)) {
        if ($e.mod_name -in @("BPModLoaderMod", "BPML_GenericFunctions")) { $e.mod_enabled = $false }
        [void]$list.Add($e)
    }
    $kb = -1; for ($i = 0; $i -lt $list.Count; $i++) { if ($list[$i].mod_name -eq "Keybinds") { $kb = $i } }
    $entry = [pscustomobject]@{ mod_name = "FrogCam"; mod_enabled = $true }
    if ($kb -ge 0) { $list.Insert($kb, $entry) } else { [void]$list.Add($entry) }
    [System.IO.File]::WriteAllText("$mods\mods.json", (ConvertTo-Json -InputObject ([object[]]$list.ToArray()) -Depth 3), $utf8)
}

# ---- zip (entries written one by one: ZipFile.CreateFromDirectory under Windows PowerShell 5.1 stores
# backslash paths, which some unzip tools turn into files named "ue4ss\UE4SS.dll" instead of folders)
function New-Zip($src, $zipPath) {
    $fs = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::CreateNew)
    $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in Get-ChildItem $src -Recurse -File) {
            $name = $f.FullName.Substring($src.Length + 1).Replace('\', '/')
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, $name, [System.IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { $zip.Dispose(); $fs.Dispose() }
}
$zips = @(
    @{ src = $full;    zip = "$dist\FrogCam-v$version-with-UE4SS.zip" },
    @{ src = $modOnly; zip = "$dist\FrogCam-v$version-mod-only.zip" }
)
foreach ($z in $zips) {
    New-Zip $z.src $z.zip
    Write-Host ("{0}  ({1:N0} KB)" -f (Split-Path $z.zip -Leaf), ((Get-Item $z.zip).Length / 1KB))
}
