# Token Gauge uninstaller
param([switch]$KeepSettings, [switch]$Yes)

$zh = [Globalization.CultureInfo]::CurrentUICulture.Name -like 'zh*'
function Say($zhText, $enText) { if ($zh) { Write-Host $zhText } else { Write-Host $enText } }

$dest = Join-Path $env:LOCALAPPDATA 'Programs\TokenGauge'
$appData = Join-Path $env:APPDATA 'TokenGauge'

Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*TokenGauge.ps1*' -and $_.ProcessId -ne $PID } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 500

foreach ($p in @(
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'Token Gauge.lnk'),
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'Uninstall Token Gauge.lnk'),
    (Join-Path ([Environment]::GetFolderPath('Startup')) 'Token Gauge.lnk'))) {
    Remove-Item -LiteralPath $p -ErrorAction SilentlyContinue
}
Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue

if (-not $KeepSettings -and (Test-Path -LiteralPath $appData)) {
    $remove = $Yes.IsPresent
    if (-not $Yes) {
        $q = if ($zh) { "同时删除设置和日志（$appData）？[y/N]" } else { "Also delete settings and logs ($appData)? [y/N]" }
        $remove = (Read-Host $q) -match '^[yY]'
    }
    if ($remove) { Remove-Item -LiteralPath $appData -Recurse -Force -ErrorAction SilentlyContinue }
}

Say 'Token Gauge 已卸载。' 'Token Gauge has been uninstalled.'
if (-not $Yes) { Read-Host ($(if ($zh) { '按回车关闭' } else { 'Press Enter to close' })) | Out-Null }
