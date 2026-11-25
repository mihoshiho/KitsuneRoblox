# Builds build\KitsuneRoblox-Setup.exe and its .sha256 from the version in KitsuneRoblox.ahk.
# -Publish also makes the GitHub release vX (needs the code pushed first). Run from Windows PowerShell.
param([switch]$Publish)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$ver = [regex]::Match((Get-Content KitsuneRoblox.ahk -Raw), 'static Version := "([\d.]+)"').Groups[1].Value
if (-not $ver) { throw 'No version found in KitsuneRoblox.ahk' }
New-Item -ItemType Directory -Force build | Out-Null
Remove-Item build\KitsuneRoblox.exe, build\KitsuneRoblox-Setup.exe* -Force -ErrorAction SilentlyContinue

# 1. script -> exe (the AutoHotkey runtime in tools is the base)
$a = Start-Process tools\ahk2exe\Ahk2Exe.exe -Wait -PassThru -ArgumentList @(
    '/in', '"KitsuneRoblox.ahk"', '/out', '"build\KitsuneRoblox.exe"', '/base', '"tools\AutoHotkey64.exe"', '/silent', 'verbose')
if ($a.ExitCode -ne 0 -or -not (Test-Path build\KitsuneRoblox.exe)) { throw "Ahk2Exe failed ($($a.ExitCode))" }

# 2. exe -> installer
& tools\inno\ISCC.exe /Q "/DAppVersion=$ver" installer.iss
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed ($LASTEXITCODE)" }

# 3. checksum the app checks before it installs an update
$hash = (Get-FileHash build\KitsuneRoblox-Setup.exe -Algorithm SHA256).Hash.ToLower()
[IO.File]::WriteAllText("$PWD\build\KitsuneRoblox-Setup.exe.sha256", "$hash  KitsuneRoblox-Setup.exe`n")
Write-Host "Built v$ver  $hash"

if ($Publish) {
    gh release create "v$ver" build\KitsuneRoblox-Setup.exe build\KitsuneRoblox-Setup.exe.sha256 --title "v$ver" --notes "KitsuneRoblox v$ver"
    if ($LASTEXITCODE -ne 0) { throw 'gh release failed' }
}
