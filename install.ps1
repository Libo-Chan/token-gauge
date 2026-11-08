# Token Gauge installer (per-user, no admin rights needed)
# Usage: double-click install.cmd, or:  powershell -ExecutionPolicy Bypass -File install.ps1 [-Autostart] [-NoAutostart] [-NoLaunch]
param([switch]$Autostart, [switch]$NoAutostart, [switch]$NoLaunch)

$ErrorActionPreference = 'Stop'
$zh = [Globalization.CultureInfo]::CurrentUICulture.Name -like 'zh*'
function Say($zhText, $enText) { if ($zh) { Write-Host $zhText } else { Write-Host $enText } }

if ($PSVersionTable.PSVersion.Major -lt 5) { Say '需要 Windows PowerShell 5.1 或更高版本。' 'Windows PowerShell 5.1 or later is required.'; exit 1 }
if ($env:OS -ne 'Windows_NT') { Say 'Token Gauge 只支持 Windows。' 'Token Gauge only runs on Windows.'; exit 1 }

$src  = Join-Path $PSScriptRoot 'src'
$dest = Join-Path $env:LOCALAPPDATA 'Programs\TokenGauge'
$main = Join-Path $dest 'TokenGauge.ps1'
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$runArgs = '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "{0}"' -f $main
$startMenu  = Join-Path ([Environment]::GetFolderPath('Programs')) 'Token Gauge.lnk'
$uninstLnk  = Join-Path ([Environment]::GetFolderPath('Programs')) 'Uninstall Token Gauge.lnk'
$startupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Token Gauge.lnk'

if (-not (Test-Path -LiteralPath (Join-Path $src 'TokenGauge.ps1'))) { Say "找不到 $src\TokenGauge.ps1，请先完整解压下载的压缩包。" "Cannot find $src\TokenGauge.ps1 - extract the whole zip first."; exit 1 }

# stop a running copy so files can be replaced
Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*TokenGauge.ps1*' -and $_.ProcessId -ne $PID } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 500

New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item -Path (Join-Path $src '*') -Destination $dest -Recurse -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'uninstall.ps1') -Destination $dest -Force
# files downloaded from the internet carry a "blocked" mark; clear it
Get-ChildItem -LiteralPath $dest -Recurse -File | Unblock-File

function New-Shortcut([string]$path, [string]$arguments, [int]$style) {
    $sh = New-Object -ComObject WScript.Shell
    $lnk = $sh.CreateShortcut($path)
    $lnk.TargetPath = $psExe
    $lnk.Arguments = $arguments
    $lnk.WorkingDirectory = $dest
    $lnk.WindowStyle = $style
    $lnk.Description = 'Token Gauge'
    $lnk.Save()
}
New-Shortcut $startMenu $runArgs 7
New-Shortcut $uninstLnk ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $dest 'uninstall.ps1')) 1

$wantAuto = $Autostart.IsPresent
if (-not $Autostart -and -not $NoAutostart) {
    $q = if ($zh) { '开机自动启动 Token Gauge？[Y/n]' } else { 'Start Token Gauge with Windows? [Y/n]' }
    $ans = Read-Host $q
    $wantAuto = ($ans -eq '' -or $ans -match '^[yY]')
}
if ($wantAuto) { New-Shortcut $startupLnk $runArgs 7 } else { Remove-Item -LiteralPath $startupLnk -ErrorAction SilentlyContinue }

Say "已安装到 $dest" "Installed to $dest"
Say '开始菜单里可以找到 "Token Gauge"。' 'You can find "Token Gauge" in the Start menu.'

if (-not $NoLaunch) {
    Start-Process -FilePath $psExe -ArgumentList $runArgs -WindowStyle Hidden
    Say '已启动，悬浮窗出现在屏幕右上角，托盘里有圆形 T 图标。' 'Started - the widget appears at the top-right; look for the round "T" tray icon.'
}
