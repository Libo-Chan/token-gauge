# Token Gauge - desktop widget for Claude Code / Codex token usage and plan quota (Windows)
# https://github.com/Libo-Chan/token-gauge  -  MIT License
# Runs on the built-in Windows PowerShell 5.1 + WPF. Nothing else to install.
# Unofficial. Not affiliated with Anthropic or OpenAI.

$ErrorActionPreference = 'Stop'
$AppName    = 'Token Gauge'
$AppVersion = '0.1.0'
$MainScript = $PSCommandPath
$ScriptDir  = $PSScriptRoot

# WPF needs an STA thread; relaunch under Windows PowerShell if started some other way
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"") -WindowStyle Hidden
    exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

# ---------- single instance ----------
$script:Mutex = New-Object System.Threading.Mutex($false, 'Local\TokenGauge_v1')
if (-not $script:Mutex.WaitOne(0)) { exit }

# ---------- paths & settings ----------
$AppDir = Join-Path $env:APPDATA 'TokenGauge'
if (-not (Test-Path -LiteralPath $AppDir)) { New-Item -ItemType Directory -Path $AppDir | Out-Null }
$SettingsPath = Join-Path $AppDir 'settings.json'
$LogPath      = Join-Path $AppDir 'error.log'

$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
$CodexDir  = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$ClaudeProjects = Join-Path $ClaudeDir 'projects'
$ClaudeCred     = Join-Path $ClaudeDir '.credentials.json'
$CodexRoots     = @((Join-Path $CodexDir 'sessions'), (Join-Path $CodexDir 'archived_sessions'))

function Log($msg) {
    try { Add-Content -LiteralPath $LogPath -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) -Encoding UTF8 } catch {}
}

$Cfg = @{ Left = $null; Top = $null; Topmost = $true; Language = 'auto'; Thresholds = @(20, 10); LocalRefreshSec = 15; QuotaRefreshSec = 120 }
if (Test-Path -LiteralPath $SettingsPath) {
    try {
        $j = [IO.File]::ReadAllText($SettingsPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        foreach ($p in $j.PSObject.Properties) { $Cfg[$p.Name] = $p.Value }
    } catch { Log "settings: $_" }
}
if ([double]$Cfg.LocalRefreshSec -lt 5) { $Cfg.LocalRefreshSec = 5 }
if ([double]$Cfg.QuotaRefreshSec -lt 60) { $Cfg.QuotaRefreshSec = 60 }   # be gentle with the quota endpoint
function Save-Settings {
    try { [IO.File]::WriteAllText($SettingsPath, ($Cfg | ConvertTo-Json), (New-Object Text.UTF8Encoding($false))) } catch { Log "save: $_" }
}

# ---------- strings (add a language: copy the 'en' block, translate, add it to $LangOrder) ----------
$Strings = @{
    'en' = @{
        Native = 'English'; Font = ''
        Header = 'TOKEN USAGE'; Today = 'tokens today'; H5 = '5-hour limit'; D7 = 'Weekly limit'
        ClaudeDetail = 'In {0} · Out {1} · Cache {2}'; CodexDetail = 'In {0} (cached {1}) · Out {2}'
        Remaining = '{0:0}% left'; Used = '{0:0}% used'; NoData = 'No data yet'; WindowReset = 'Window has reset, waiting for new data'; NotStarted = '{0:0}% used (window not started)'
        ResetIn = 'resets in {0} · {1}'; DaysHours = '{0}d {1}h'; ResetNow = 'resetting now'
        Footer = 'Updated {0} · refreshes every {1}s · drag to move'
        Fetching = 'Fetching quota…'
        NoCred = 'Claude Code login not found. Install the Claude Code CLI, run claude once and sign in with your subscription.'
        Expired = 'Login token expired. Run claude once in a terminal to renew it.'
        Invalid = 'Login token rejected. Run claude and sign in again.'
        TooMany = 'Quota endpoint rate-limited, retrying later.'
        NetErr = 'Could not reach the quota endpoint, retrying later.'
        NoClaudeLogs = 'No local Claude Code sessions on this PC (cloud sessions leave no local logs).'
        NoCodexDir = 'Codex sessions folder not found: {0}'
        NoCodexRecent = 'No Codex activity in the last 7 days. Use Codex once to see the quota.'
        AlertTitle = '{0} running low'; AlertBody = 'Only {0:0}% left'
        TipRefresh = 'Refresh now'; TipPin = 'Always on top'; TipHide = 'Hide to tray (double-click the tray icon to restore)'
        MenuShow = 'Show / hide'; MenuRefresh = 'Refresh now'; MenuTop = 'Always on top'; MenuAuto = 'Start with Windows'; MenuFolder = 'Open settings folder'; MenuExit = 'Exit'
        MenuLang = 'Language'; LangAuto = 'Follow system'
        Tip5h = '{0} 5h: {1:0}% left'
    }
    'zh-CN' = @{
        Native = '简体中文'; Font = 'Microsoft YaHei UI'
        Header = 'TOKEN 用量'; Today = '今日 tokens'; H5 = '5 小时额度'; D7 = '每周额度'
        ClaudeDetail = '输入 {0} · 输出 {1} · 缓存 {2}'; CodexDetail = '输入 {0}（缓存 {1}）· 输出 {2}'
        Remaining = '剩余 {0:0}%'; Used = '已用 {0:0}%'; NoData = '暂无数据'; WindowReset = '窗口已重置，等待新数据'; NotStarted = '已用 {0:0}%（窗口尚未开始计时）'
        ResetIn = '{0} 后重置 · {1}'; DaysHours = '{0} 天 {1} 小时'; ResetNow = '即将重置'
        Footer = '更新于 {0} · 每 {1} 秒刷新 · 可拖动'
        Fetching = '正在获取额度…'
        NoCred = '未找到 Claude Code 登录信息。安装 Claude Code 命令行版，运行一次 claude 并用订阅账号登录即可。'
        Expired = '登录令牌已过期。在终端运行一次 claude，令牌会自动续期。'
        Invalid = '登录令牌无效，请运行 claude 重新登录。'
        TooMany = '额度查询过于频繁，稍后自动重试。'
        NetErr = '额度获取失败（网络），稍后自动重试。'
        NoClaudeLogs = '本机没有 Claude Code 本地会话记录（云端会话不会在本机留下记录）。'
        NoCodexDir = '未找到 Codex 会话目录：{0}'
        NoCodexRecent = '最近 7 天没有 Codex 使用记录，用一次 Codex 后显示额度。'
        AlertTitle = '{0} 不足'; AlertBody = '仅剩 {0:0}%'
        TipRefresh = '立即刷新'; TipPin = '窗口置顶'; TipHide = '隐藏到托盘（双击托盘图标恢复）'
        MenuShow = '显示 / 隐藏'; MenuRefresh = '立即刷新'; MenuTop = '窗口置顶'; MenuAuto = '开机自动启动'; MenuFolder = '打开设置文件夹'; MenuExit = '退出'
        MenuLang = '语言'; LangAuto = '跟随系统'
        Tip5h = '{0} 5h 剩余 {1:0}%'
    }
    'zh-TW' = @{
        Native = '繁體中文'; Font = 'Microsoft JhengHei UI'
        Header = 'TOKEN 用量'; Today = '今日 tokens'; H5 = '5 小時額度'; D7 = '每週額度'
        ClaudeDetail = '輸入 {0} · 輸出 {1} · 快取 {2}'; CodexDetail = '輸入 {0}（快取 {1}）· 輸出 {2}'
        Remaining = '剩餘 {0:0}%'; Used = '已用 {0:0}%'; NoData = '暫無資料'; WindowReset = '額度週期已重置，等待新資料'; NotStarted = '已用 {0:0}%（週期尚未開始計時）'
        ResetIn = '{0} 後重置 · {1}'; DaysHours = '{0} 天 {1} 小時'; ResetNow = '即將重置'
        Footer = '更新於 {0} · 每 {1} 秒重新整理 · 可拖曳'
        Fetching = '正在取得額度…'
        NoCred = '找不到 Claude Code 登入資訊。請安裝 Claude Code 命令列版，執行一次 claude 並以訂閱帳號登入。'
        Expired = '登入權杖已過期。在終端機執行一次 claude 即可自動續期。'
        Invalid = '登入權杖無效，請執行 claude 重新登入。'
        TooMany = '額度查詢過於頻繁，稍後自動重試。'
        NetErr = '無法取得額度（網路問題），稍後自動重試。'
        NoClaudeLogs = '這台電腦上沒有 Claude Code 本機工作階段紀錄（雲端工作階段不會在本機留下紀錄）。'
        NoCodexDir = '找不到 Codex 工作階段資料夾：{0}'
        NoCodexRecent = '最近 7 天沒有 Codex 使用紀錄，使用一次 Codex 後即會顯示額度。'
        AlertTitle = '{0} 即將用完'; AlertBody = '僅剩 {0:0}%'
        TipRefresh = '立即重新整理'; TipPin = '視窗置頂'; TipHide = '隱藏到系統匣（按兩下系統匣圖示即可還原）'
        MenuShow = '顯示 / 隱藏'; MenuRefresh = '立即重新整理'; MenuTop = '視窗置頂'; MenuAuto = '開機時自動啟動'; MenuFolder = '開啟設定資料夾'; MenuExit = '結束'
        MenuLang = '語言'; LangAuto = '跟隨系統'
        Tip5h = '{0} 5h 剩餘 {1:0}%'
    }
    'ja' = @{
        Native = '日本語'; Font = 'Yu Gothic UI'
        Header = 'トークン使用量'; Today = '本日のトークン'; H5 = '5 時間の上限'; D7 = '週間の上限'
        ClaudeDetail = '入力 {0} · 出力 {1} · キャッシュ {2}'; CodexDetail = '入力 {0}（キャッシュ {1}）· 出力 {2}'
        Remaining = '残り {0:0}%'; Used = '{0:0}% 使用'; NoData = 'データなし'; WindowReset = 'リセット済み。新しいデータを待っています'; NotStarted = '{0:0}% 使用（期間未開始）'
        ResetIn = 'あと {0} でリセット · {1}'; DaysHours = '{0} 日 {1} 時間'; ResetNow = 'まもなくリセット'
        Footer = '更新 {0} · {1} 秒ごとに更新 · ドラッグで移動'
        Fetching = '上限を取得中…'
        NoCred = 'Claude Code のログイン情報が見つかりません。Claude Code CLI をインストールし、claude を一度実行してサブスクリプションでログインしてください。'
        Expired = 'ログイントークンの有効期限が切れています。ターミナルで claude を一度実行すると更新されます。'
        Invalid = 'ログイントークンが無効です。claude を実行して再ログインしてください。'
        TooMany = '問い合わせが多すぎます。しばらくして自動で再試行します。'
        NetErr = '上限を取得できませんでした（ネットワーク）。しばらくして自動で再試行します。'
        NoClaudeLogs = 'この PC に Claude Code のローカルセッションはありません（クラウドセッションはローカルに記録されません）。'
        NoCodexDir = 'Codex のセッションフォルダーが見つかりません: {0}'
        NoCodexRecent = '過去 7 日間 Codex の使用履歴がありません。一度 Codex を使うと上限が表示されます。'
        AlertTitle = '{0} が残りわずか'; AlertBody = '残り {0:0}%'
        TipRefresh = '今すぐ更新'; TipPin = '常に手前に表示'; TipHide = 'トレイに隠す（トレイアイコンをダブルクリックで再表示）'
        MenuShow = '表示 / 非表示'; MenuRefresh = '今すぐ更新'; MenuTop = '常に手前に表示'; MenuAuto = 'Windows 起動時に開始'; MenuFolder = '設定フォルダーを開く'; MenuExit = '終了'
        MenuLang = '言語'; LangAuto = 'システムに合わせる'
        Tip5h = '{0} 5h 残り {1:0}%'
    }
    'ko' = @{
        Native = '한국어'; Font = 'Malgun Gothic'
        Header = '토큰 사용량'; Today = '오늘 토큰'; H5 = '5시간 한도'; D7 = '주간 한도'
        ClaudeDetail = '입력 {0} · 출력 {1} · 캐시 {2}'; CodexDetail = '입력 {0} (캐시 {1}) · 출력 {2}'
        Remaining = '{0:0}% 남음'; Used = '{0:0}% 사용'; NoData = '데이터 없음'; WindowReset = '한도가 초기화됨, 새 데이터 대기 중'; NotStarted = '{0:0}% 사용 (기간 시작 전)'
        ResetIn = '{0} 후 초기화 · {1}'; DaysHours = '{0}일 {1}시간'; ResetNow = '곧 초기화'
        Footer = '{0} 업데이트 · {1}초마다 새로 고침 · 드래그하여 이동'
        Fetching = '한도 가져오는 중…'
        NoCred = 'Claude Code 로그인 정보를 찾을 수 없습니다. Claude Code CLI를 설치하고 claude를 한 번 실행해 구독 계정으로 로그인하세요.'
        Expired = '로그인 토큰이 만료되었습니다. 터미널에서 claude를 한 번 실행하면 갱신됩니다.'
        Invalid = '로그인 토큰이 유효하지 않습니다. claude를 실행해 다시 로그인하세요.'
        TooMany = '요청이 너무 많습니다. 잠시 후 자동으로 다시 시도합니다.'
        NetErr = '한도를 가져오지 못했습니다(네트워크). 잠시 후 자동으로 다시 시도합니다.'
        NoClaudeLogs = '이 PC에 Claude Code 로컬 세션이 없습니다(클라우드 세션은 로컬에 기록되지 않음).'
        NoCodexDir = 'Codex 세션 폴더를 찾을 수 없습니다: {0}'
        NoCodexRecent = '최근 7일간 Codex 사용 기록이 없습니다. Codex를 한 번 사용하면 한도가 표시됩니다.'
        AlertTitle = '{0} 부족'; AlertBody = '{0:0}%만 남음'
        TipRefresh = '지금 새로 고침'; TipPin = '항상 위에 표시'; TipHide = '트레이로 숨기기(트레이 아이콘을 두 번 클릭하면 복원)'
        MenuShow = '표시 / 숨기기'; MenuRefresh = '지금 새로 고침'; MenuTop = '항상 위에 표시'; MenuAuto = 'Windows 시작 시 실행'; MenuFolder = '설정 폴더 열기'; MenuExit = '종료'
        MenuLang = '언어'; LangAuto = '시스템 설정 따르기'
        Tip5h = '{0} 5h {1:0}% 남음'
    }
}
$LangOrder = @('en', 'zh-CN', 'zh-TW', 'ja', 'ko')

function Resolve-Lang([string]$pref) {
    if ($pref -eq 'zh') { $pref = 'zh-CN' }                       # settings from 0.1.0 previews
    if ($Strings.ContainsKey($pref)) { return $pref }
    $ui = [Globalization.CultureInfo]::CurrentUICulture.Name
    if ($ui -match '^zh-(TW|HK|MO)$' -or $ui -like 'zh-Hant*') { return 'zh-TW' }
    if ($ui -like 'zh*') { return 'zh-CN' }
    if ($ui -like 'ja*') { return 'ja' }
    if ($ui -like 'ko*') { return 'ko' }
    return 'en'
}
$Lang = Resolve-Lang ([string]$Cfg.Language)
$T = $Strings[$Lang]

# ---------- state ----------
$S = @{
    Day = (Get-Date).Date
    DayStartUtc = ''
    Files = @{}
    Seen = New-Object 'System.Collections.Generic.HashSet[string]'
    Claude = @{ In = [long]0; Out = [long]0; CW = [long]0; CR = [long]0; Found = $false }
    Codex  = @{ In = [long]0; Cached = [long]0; Out = [long]0; Total = [long]0; Found = $false; RateTs = ''; H5 = $null; D7 = $null; Plan = '' }
    CQ = @{ H5 = $null; D7 = $null; Plan = ''; Msg = 'Fetching' }   # Msg holds a key into $T
    ClaudeDirs = $null; ClaudeDirsAt = $null
    Http = $null
    NextLocal = [DateTime]::MinValue
    NextQuota = [DateTime]::MinValue
    LastUpdate = $null
    Alerted = @{}
    TrayLevel = ''
}
function Reset-Day {
    $S.Day = (Get-Date).Date
    $S.DayStartUtc = $S.Day.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss')
    $S.Files = @{}
    $S.Seen.Clear()
    $S.Claude.In = 0; $S.Claude.Out = 0; $S.Claude.CW = 0; $S.Claude.CR = 0
    $S.Codex.In = 0; $S.Codex.Cached = 0; $S.Codex.Out = 0; $S.Codex.Total = 0
}
Reset-Day

# ---------- incremental jsonl reader (shared read, complete lines only) ----------
function Read-NewLines([string]$path) {
    $st = $S.Files[$path]
    if (-not $st) { $st = @{ Offset = [long]0 }; $S.Files[$path] = $st }
    $len = (New-Object System.IO.FileInfo($path)).Length
    if ($len -lt $st.Offset) { $st.Offset = [long]0 }
    if ($len -eq $st.Offset) { return ,@() }
    $fs = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        [void]$fs.Seek($st.Offset, [IO.SeekOrigin]::Begin)
        $count = [int]($len - $st.Offset)
        $buf = New-Object byte[] $count
        $n = 0
        while ($n -lt $count) { $r = $fs.Read($buf, $n, $count - $n); if ($r -le 0) { break }; $n += $r }
    } finally { $fs.Dispose() }
    if ($n -le 0) { return ,@() }
    $last = [Array]::LastIndexOf($buf, [byte]10, $n - 1)
    if ($last -lt 0) { return ,@() }
    $text = [Text.Encoding]::UTF8.GetString($buf, 0, $last + 1)
    $st.Offset += ($last + 1)
    return ,$text.Split([char]10)
}

function Walk-Jsonl([string]$dir, [datetime]$since, $list, [int]$depth) {
    if ($depth -gt 8) { return }
    try { foreach ($f in [IO.Directory]::GetFiles($dir, '*.jsonl')) { try { if ([IO.File]::GetLastWriteTime($f) -ge $since) { $list.Add($f) } } catch {} } } catch {}
    try { foreach ($d in [IO.Directory]::GetDirectories($dir)) { Walk-Jsonl $d $since $list ($depth + 1) } } catch {}
}
function Get-JsonlFiles([string]$root, [datetime]$since) {
    $list = New-Object System.Collections.Generic.List[string]
    if (-not [IO.Directory]::Exists($root)) { return ,$list }
    Walk-Jsonl $root $since $list 0
    return ,$list
}

# ---------- Claude Code: local session logs ----------
$ReTs    = New-Object System.Text.RegularExpressions.Regex('"timestamp":"([^"]+)"', [System.Text.RegularExpressions.RegexOptions]::RightToLeft)
$ReTsFwd = [regex]'"timestamp":"([^"]+)"'
$ReMsgId = [regex]'"id":"(msg_[^"]+)"'
$ReReq   = [regex]'"requestId":"([^"]+)"'
$ReIn    = [regex]'"input_tokens":(\d+)'
$ReOut   = [regex]'"output_tokens":(\d+)'
$ReCW    = [regex]'"cache_creation_input_tokens":(\d+)'
$ReCR    = [regex]'"cache_read_input_tokens":(\d+)'
function NumOf($re, [string]$s) { $m = $re.Match($s); if ($m.Success) { [long]$m.Groups[1].Value } else { [long]0 } }

# The Claude desktop app keeps local Claude Code sessions in its own folders; look for any "<...>\.claude\projects"
$SkipDirRe = [regex]'\\(Cache|Code Cache|GPUCache|node_modules|vm_bundles|IndexedDB|Service Worker|blob_storage|Crashpad|ShaderCache|GrShaderCache|DawnGraphiteCache|DawnWebGPUCache|GPUPersistentCache|Local Storage|Session Storage|WebStorage|Network|Dictionaries)$'
function Find-ProjectDirs([string]$dir, $acc, [int]$depth) {
    if ($depth -gt 10) { return }
    $subs = $null
    try { $subs = [IO.Directory]::GetDirectories($dir) } catch { return }
    foreach ($d in $subs) {
        if ($SkipDirRe.IsMatch($d)) { continue }
        if ([IO.Path]::GetFileName($d) -eq 'projects' -and [IO.Path]::GetFileName($dir) -eq '.claude') { $acc.Add($d); continue }
        Find-ProjectDirs $d $acc ($depth + 1)
    }
}
function Get-ClaudeProjectDirs {
    if ($null -ne $S.ClaudeDirsAt -and [DateTime]::UtcNow -lt $S.ClaudeDirsAt) { return ,$S.ClaudeDirs }
    $acc = New-Object System.Collections.Generic.List[string]
    if ([IO.Directory]::Exists($ClaudeProjects)) { $acc.Add($ClaudeProjects) }
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($r in @((Join-Path $env:LOCALAPPDATA 'Claude-3p'), (Join-Path $env:LOCALAPPDATA 'Claude'), (Join-Path $env:APPDATA 'Claude'), (Join-Path $env:LOCALAPPDATA 'Claude-Data'))) { if ([IO.Directory]::Exists($r)) { $roots.Add($r) } }
    try { foreach ($p in [IO.Directory]::GetDirectories((Join-Path $env:LOCALAPPDATA 'Packages'), '*laude*')) { $roots.Add($p) } } catch {}
    foreach ($r in $roots) { Find-ProjectDirs $r $acc 0 }
    $S.ClaudeDirs = $acc
    $S.ClaudeDirsAt = [DateTime]::UtcNow.AddMinutes(10)
    return ,$acc
}

function Update-Claude {
    $dirs = Get-ClaudeProjectDirs
    if ($dirs.Count -eq 0) { return }
    $S.Claude.Found = $true
    foreach ($dir in $dirs) {
        foreach ($f in (Get-JsonlFiles $dir $S.Day)) {
            try { $lines = Read-NewLines $f } catch { Log "read $f : $_"; continue }
            foreach ($line in $lines) {
                if ($line.Length -lt 50) { continue }
                if (-not $line.Contains('"type":"assistant"')) { continue }
                $ui = $line.LastIndexOf('"usage":{')
                if ($ui -lt 0) { continue }
                $tm = $ReTs.Match($line)
                if (-not $tm.Success) { continue }
                if ([string]::CompareOrdinal($tm.Groups[1].Value, $S.DayStartUtc) -lt 0) { continue }
                $mid = $ReMsgId.Match($line); $rq = $ReReq.Match($line)
                if ($mid.Success -or $rq.Success) {
                    if (-not $S.Seen.Add('c|' + $mid.Groups[1].Value + '|' + $rq.Groups[1].Value)) { continue }
                }
                $u = $line.Substring($ui, [Math]::Min(1200, $line.Length - $ui))
                $S.Claude.In  += NumOf $ReIn  $u
                $S.Claude.Out += NumOf $ReOut $u
                $S.Claude.CW  += NumOf $ReCW  $u
                $S.Claude.CR  += NumOf $ReCR  $u
            }
        }
    }
}

# ---------- Codex: local session logs (tokens + rate limits) ----------
function Convert-CodexWindow($w, [string]$ts) {
    if (-not $w) { return $null }
    $reset = $null
    if ($w.resets_at) { $reset = [DateTimeOffset]::FromUnixTimeSeconds([long]$w.resets_at) }
    elseif ($w.resets_in_seconds) { $reset = [DateTimeOffset]::Parse($ts, [Globalization.CultureInfo]::InvariantCulture).AddSeconds([double]$w.resets_in_seconds) }
    return @{ Used = [double]$w.used_percent; Reset = $reset }
}

function Update-Codex {
    $files = New-Object System.Collections.Generic.List[string]
    $newest = $null; $newestT = [datetime]::MinValue
    foreach ($root in $CodexRoots) {
        if (-not [IO.Directory]::Exists($root)) { continue }
        $S.Codex.Found = $true
        foreach ($f in (Get-JsonlFiles $root $S.Day.AddDays(-7))) {
            $t = [IO.File]::GetLastWriteTime($f)
            if ($t -ge $S.Day) { $files.Add($f) }
            if ($t -gt $newestT) { $newestT = $t; $newest = $f }
        }
    }
    if ($newest -and -not $files.Contains($newest)) { $files.Add($newest) }   # newest file carries the latest rate limits
    foreach ($f in $files) {
        $leaf = [IO.Path]::GetFileName($f)
        try { $lines = Read-NewLines $f } catch { Log "read $f : $_"; continue }
        foreach ($line in $lines) {
            if (-not $line.Contains('"token_count"')) { continue }
            # take the timestamp from the raw text: PowerShell 7's ConvertFrom-Json would turn it into a DateTime
            $tm = $ReTsFwd.Match($line)
            if (-not $tm.Success) { continue }
            $ts = $tm.Groups[1].Value
            try { $o = $line | ConvertFrom-Json } catch { continue }
            $p = $o.payload
            if (-not $p -or $p.type -ne 'token_count') { continue }
            if ($p.info -and $p.info.last_token_usage -and [string]::CompareOrdinal($ts, $S.DayStartUtc) -ge 0) {
                $key = 'x|' + $leaf + '|' + $p.info.total_token_usage.total_tokens
                if ($S.Seen.Add($key)) {
                    $l = $p.info.last_token_usage
                    $S.Codex.In     += [long]$l.input_tokens
                    $S.Codex.Cached += [long]$l.cached_input_tokens
                    $S.Codex.Out    += [long]$l.output_tokens
                    $S.Codex.Total  += [long]$l.total_tokens
                }
            }
            $rl = $p.rate_limits
            if ($rl -and $rl.primary -and [string]::CompareOrdinal($ts, $S.Codex.RateTs) -gt 0) {
                $S.Codex.RateTs = $ts
                $S.Codex.H5 = Convert-CodexWindow $rl.primary $ts
                $S.Codex.D7 = Convert-CodexWindow $rl.secondary $ts
                if ($rl.plan_type) { $S.Codex.Plan = [string]$rl.plan_type }
            }
        }
    }
}

function Update-Local {
    try { Update-Claude } catch { Log "claude: $_" }
    try { Update-Codex }  catch { Log "codex: $_" }
    $S.LastUpdate = Get-Date
}

# ---------- Claude plan quota (read-only, async) ----------
# Reads the token Claude Code saved after `claude` login and asks the same usage endpoint Claude Code uses.
# The token is never modified or refreshed here; Claude Code itself renews it whenever you run it.
$FetchScript = {
    param($credPath, $ua)
    $out = @{ ok = $false; err = ''; code = 0; plan = ''; data = $null }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        if (-not (Test-Path -LiteralPath $credPath)) { $out.err = 'nocred'; return $out }
        $o = ([IO.File]::ReadAllText($credPath, [Text.Encoding]::UTF8) | ConvertFrom-Json).claudeAiOauth
        if (-not $o -or -not $o.accessToken) { $out.err = 'nocred'; return $out }
        $out.plan = [string]$o.subscriptionType
        if ($o.expiresAt) {
            if ([DateTimeOffset]::FromUnixTimeMilliseconds([long]$o.expiresAt) -lt [DateTimeOffset]::UtcNow) { $out.err = 'expired'; return $out }
        }
        $h = @{ 'Authorization' = "Bearer $($o.accessToken)"; 'anthropic-beta' = 'oauth-2025-04-20'; 'Accept' = 'application/json' }
        $out.data = Invoke-RestMethod -Uri 'https://api.anthropic.com/api/oauth/usage' -Headers $h -Method Get -TimeoutSec 20 -UseBasicParsing -UserAgent $ua
        $out.ok = $true
    } catch {
        $out.err = $_.Exception.Message
        try { $out.code = [int]$_.Exception.Response.StatusCode } catch {}
    }
    return $out
}

function Start-ClaudeQuotaFetch {
    if ($S.Http) { return }
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript($FetchScript).AddArgument($ClaudeCred).AddArgument("TokenGauge/$AppVersion")
    $S.Http = @{ PS = $ps; RS = $rs; H = $ps.BeginInvoke() }
}

function Convert-ClaudeWindow($w) {
    if (-not $w) { return $null }
    $reset = $null
    if ($w.resets_at) {
        if ($w.resets_at -is [datetime]) { $reset = [DateTimeOffset]$w.resets_at }
        else { $reset = [DateTimeOffset]::Parse([string]$w.resets_at, [Globalization.CultureInfo]::InvariantCulture) }
    }
    return @{ Used = [double]$w.utilization; Reset = $reset }
}

function Poll-ClaudeQuota {
    if (-not $S.Http -or -not $S.Http.H.IsCompleted) { return }
    $res = $null
    try { $r = $S.Http.PS.EndInvoke($S.Http.H); if ($r.Count -gt 0) { $res = $r[$r.Count - 1] } } catch { Log "fetch end: $_" }
    try { $S.Http.PS.Dispose(); $S.Http.RS.Dispose() } catch {}
    $S.Http = $null
    if (-not $res) { return }
    if ($res.plan) { $S.CQ.Plan = $res.plan }
    if ($res.ok) {
        $S.CQ.H5 = Convert-ClaudeWindow $res.data.five_hour
        $S.CQ.D7 = Convert-ClaudeWindow $res.data.seven_day
        $S.CQ.Msg = ''
        return
    }
    switch ($res.err) {
        'nocred'  { $S.CQ.Msg = 'NoCred' }
        'expired' { $S.CQ.Msg = 'Expired' }
        default {
            if ($res.code -eq 401 -or $res.code -eq 403) { $S.CQ.Msg = 'Invalid' }
            elseif ($res.code -eq 429) { $S.CQ.Msg = 'TooMany'; $S.NextQuota = [DateTime]::UtcNow.AddMinutes(5) }
            else { $S.CQ.Msg = 'NetErr'; Log "quota: $($res.code) $($res.err)" }
        }
    }
}

# ---------- UI ----------
function Esc([string]$s) { [Security.SecurityElement]::Escape($s) }

$SectionXaml = @'
<StackPanel>
  <Grid Margin="0,12,0,0">
    <StackPanel Orientation="Horizontal">
      <Ellipse Width="8" Height="8" Fill="ACCENT" VerticalAlignment="Center" Margin="0,0,8,0"/>
      <TextBlock Text="TITLE" Foreground="#F2FFFFFF" FontSize="13" FontWeight="SemiBold"/>
    </StackPanel>
    <Border HorizontalAlignment="Right" CornerRadius="4" Background="#1AFFFFFF" Padding="7,1,7,2">
      <TextBlock x:Name="P_Plan" Text="—" FontSize="10" Foreground="#B3FFFFFF"/>
    </Border>
  </Grid>
  <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
    <TextBlock x:Name="P_Today" Text="0" FontSize="26" FontWeight="SemiBold" Foreground="White"/>
    <TextBlock x:Name="P_TodayLbl" Text=" " Style="{StaticResource Small}" VerticalAlignment="Bottom" Margin="7,0,0,6"/>
  </StackPanel>
  <TextBlock x:Name="P_Detail" Style="{StaticResource Small}" TextWrapping="Wrap" Text=" "/>
  BAR_P_H5
  BAR_P_D7
  <TextBlock x:Name="P_Msg" FontSize="11" Foreground="#FFFFB340" TextWrapping="Wrap" Visibility="Collapsed" Margin="0,8,0,0"/>
</StackPanel>
'@
$BarXaml = @'
<Grid Margin="0,10,0,0">
  <TextBlock x:Name="N_Lbl" Text=" " Style="{StaticResource Small}"/>
  <TextBlock x:Name="N_Pct" HorizontalAlignment="Right" FontSize="11" FontWeight="SemiBold" Foreground="White" Text="—"/>
</Grid>
<Grid x:Name="N_Bar" Height="6" Margin="0,5,0,0">
  <Grid.ColumnDefinitions><ColumnDefinition Width="0*"/><ColumnDefinition Width="1*"/></Grid.ColumnDefinitions>
  <Border Grid.ColumnSpan="2" CornerRadius="3" Background="#1FFFFFFF"/>
  <Border x:Name="N_Fill" Grid.Column="0" CornerRadius="3" Background="#FF34C759"/>
</Grid>
<TextBlock x:Name="N_Reset" Style="{StaticResource Small}" TextWrapping="Wrap" Margin="0,4,0,0" Text=" "/>
'@
function New-Section($prefix, $title, $accent) {
    $x = $SectionXaml.Replace('BAR_P_H5', $BarXaml.Replace('N_', "${prefix}_H5_"))
    $x = $x.Replace('BAR_P_D7', $BarXaml.Replace('N_', "${prefix}_D7_"))
    return $x.Replace('P_', "${prefix}_").Replace('TITLE', $title).Replace('ACCENT', $accent)
}

$WindowXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Token Gauge" Width="310" SizeToContent="Height"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" ShowInTaskbar="False" Topmost="True"
        UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
  <Window.Resources>
    <Style x:Key="Small" TargetType="TextBlock">
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="Foreground" Value="#8CFFFFFF"/>
    </Style>
    <Style x:Key="IconBtn" TargetType="Button">
      <Setter Property="Width" Value="24"/><Setter Property="Height" Value="24"/>
      <Setter Property="Margin" Value="2,0,0,0"/>
      <Setter Property="Foreground" Value="#80FFFFFF"/>
      <Setter Property="FontFamily" Value="Segoe Fluent Icons, Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="Transparent" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="#22FFFFFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border x:Name="Root" Margin="12" CornerRadius="14" Background="#F51B1D22" BorderBrush="#22FFFFFF" BorderThickness="1" Padding="16,10,16,14">
    <Border.Effect><DropShadowEffect BlurRadius="16" ShadowDepth="2" Opacity="0.4"/></Border.Effect>
    <StackPanel>
      <Grid>
        <TextBlock x:Name="HeaderText" Text=" " FontSize="11" FontWeight="SemiBold" Foreground="#73FFFFFF" VerticalAlignment="Center"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="BtnRefresh" Style="{StaticResource IconBtn}" Content="&#xE72C;"/>
          <Button x:Name="BtnPin" Style="{StaticResource IconBtn}" Content="&#xE718;"/>
          <Button x:Name="BtnHide" Style="{StaticResource IconBtn}" Content="&#xE921;"/>
        </StackPanel>
      </Grid>
      SECTION_CLAUDE
      <Border Height="1" Background="#14FFFFFF" Margin="0,14,0,0"/>
      SECTION_CODEX
      <TextBlock x:Name="Footer" Style="{StaticResource Small}" FontSize="10" TextWrapping="Wrap" Foreground="#59FFFFFF" Margin="0,12,0,0" Text=" "/>
    </StackPanel>
  </Border>
</Window>
'@
$WindowXaml = $WindowXaml.Replace('SECTION_CLAUDE', (New-Section 'C' 'Claude Code' '#FFE0875F')).Replace('SECTION_CODEX', (New-Section 'X' 'Codex' '#FF6E8BFF'))
$app = New-Object System.Windows.Application
$app.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
$win = [Windows.Markup.XamlReader]::Parse($WindowXaml)

$UI = @{}
foreach ($n in 'Root','BtnRefresh','BtnPin','BtnHide','Footer','HeaderText') { $UI[$n] = $win.FindName($n) }
foreach ($p in 'C','X') {
    foreach ($n in 'Plan','Today','TodayLbl','Detail','Msg') { $UI["${p}_$n"] = $win.FindName("${p}_$n") }
    foreach ($b in 'H5','D7') { foreach ($n in 'Pct','Bar','Fill','Reset','Lbl') { $UI["${p}_${b}_$n"] = $win.FindName("${p}_${b}_$n") } }
}

$BC = New-Object System.Windows.Media.BrushConverter
$Brush = @{ Green = $BC.ConvertFromString('#FF34C759'); Amber = $BC.ConvertFromString('#FFFF9F0A'); Red = $BC.ConvertFromString('#FFFF453A'); Dim = $BC.ConvertFromString('#80FFFFFF'); Pin = $BC.ConvertFromString('#FFFFB340') }
function Get-Level([double]$remain) { if ($remain -le 20) { 'Red' } elseif ($remain -le 50) { 'Amber' } else { 'Green' } }

function Format-Tokens([long]$n) {
    $ci = [Globalization.CultureInfo]::InvariantCulture
    if ($n -ge 1e9) { return ($n / 1e9).ToString('0.00', $ci) + 'B' }
    if ($n -ge 1e6) { return ($n / 1e6).ToString('0.00', $ci) + 'M' }
    if ($n -ge 1e4) { return ($n / 1e3).ToString('0.0', $ci) + 'K' }
    return $n.ToString('N0', $ci)
}
function Format-Reset($reset, [bool]$long) {
    $span = $reset - [DateTimeOffset]::Now
    if ($span.TotalSeconds -le 0) { return $T.ResetNow }
    if ($span.TotalDays -ge 1) { $cd = $T.DaysHours -f [int][Math]::Floor($span.TotalDays), $span.Hours }
    else { $cd = '{0:00}:{1:00}:{2:00}' -f [int][Math]::Floor($span.TotalHours), $span.Minutes, $span.Seconds }
    $local = $reset.LocalDateTime
    $at = if ($long) { $local.ToString('M/d HH:mm') } else { $local.ToString('HH:mm') }
    return $T.ResetIn -f $cd, $at
}

# draws one quota bar; returns remaining % or $null
function Set-Bar($key, $w, [bool]$long) {
    $pct = $UI["${key}_Pct"]; $bar = $UI["${key}_Bar"]; $fill = $UI["${key}_Fill"]; $rst = $UI["${key}_Reset"]
    if (-not $w) {
        $pct.Text = '—'; $pct.Foreground = $Brush.Dim; $rst.Text = $T.NoData
        $bar.ColumnDefinitions[0].Width = New-Object System.Windows.GridLength(0, 'Star')
        $bar.ColumnDefinitions[1].Width = New-Object System.Windows.GridLength(1, 'Star')
        return $null
    }
    $used = $w.Used
    $expired = ($w.Reset -and $w.Reset -le [DateTimeOffset]::Now)
    if ($expired) { $used = 0 }
    $remain = [Math]::Max(0, [Math]::Min(100, 100 - $used))
    $lvl = Get-Level $remain
    $bar.ColumnDefinitions[0].Width = New-Object System.Windows.GridLength($remain, 'Star')
    $bar.ColumnDefinitions[1].Width = New-Object System.Windows.GridLength((100 - $remain), 'Star')
    $fill.Background = $Brush[$lvl]
    $pct.Foreground = $Brush[$lvl]
    $pct.Text = $T.Remaining -f $remain
    if ($expired) { $rst.Text = $T.WindowReset }
    elseif ($w.Reset) { $rst.Text = (Format-Reset $w.Reset $long) + '  ·  ' + ($T.Used -f $used) }
    else { $rst.Text = $T.NotStarted -f $used }
    return $remain
}

function Plan-Name([string]$p) { if (-not $p) { return '—' }; return $p.Substring(0,1).ToUpper() + $p.Substring(1) }

function Render {
    $c = $S.Claude
    $UI.C_Today.Text = Format-Tokens ($c.In + $c.Out + $c.CW + $c.CR)
    $UI.C_Detail.Text = $T.ClaudeDetail -f (Format-Tokens $c.In), (Format-Tokens $c.Out), (Format-Tokens ($c.CW + $c.CR))
    $UI.C_Plan.Text = Plan-Name $S.CQ.Plan
    $cr5 = Set-Bar 'C_H5' $S.CQ.H5 $false
    $cr7 = Set-Bar 'C_D7' $S.CQ.D7 $true
    $cmsg = if ($S.CQ.Msg) { $T[$S.CQ.Msg] } else { '' }
    if (-not $cmsg -and -not $c.Found) { $cmsg = $T.NoClaudeLogs }
    if ($cmsg) { $UI.C_Msg.Text = $cmsg; $UI.C_Msg.Visibility = 'Visible' } else { $UI.C_Msg.Visibility = 'Collapsed' }

    $x = $S.Codex
    $UI.X_Today.Text = Format-Tokens $x.Total
    $UI.X_Detail.Text = $T.CodexDetail -f (Format-Tokens $x.In), (Format-Tokens $x.Cached), (Format-Tokens $x.Out)
    $UI.X_Plan.Text = Plan-Name $x.Plan
    $xr5 = Set-Bar 'X_H5' $x.H5 $false
    $xr7 = Set-Bar 'X_D7' $x.D7 $true
    if (-not $x.Found) { $UI.X_Msg.Text = $T.NoCodexDir -f $CodexDir; $UI.X_Msg.Visibility = 'Visible' }
    elseif (-not $x.H5) { $UI.X_Msg.Text = $T.NoCodexRecent; $UI.X_Msg.Visibility = 'Visible' }
    else { $UI.X_Msg.Visibility = 'Collapsed' }

    if ($S.LastUpdate) { $UI.Footer.Text = $T.Footer -f $S.LastUpdate.ToString('HH:mm:ss'), $Cfg.LocalRefreshSec }

    $worst = 100
    foreach ($v in @($cr5, $cr7, $xr5, $xr7)) { if ($null -ne $v -and $v -lt $worst) { $worst = $v } }
    Set-TrayLevel (Get-Level $worst)
    $tip = $AppName
    if ($null -ne $cr5) { $tip += "`n" + ($T.Tip5h -f 'Claude', $cr5) }
    if ($null -ne $xr5) { $tip += "`n" + ($T.Tip5h -f 'Codex', $xr5) }
    if ($tip.Length -gt 63) { $tip = $tip.Substring(0, 63) }
    $Tray.Text = $tip

    Check-Alert 'C5' ('Claude Code ' + $T.H5) $cr5 $S.CQ.H5
    Check-Alert 'C7' ('Claude Code ' + $T.D7) $cr7 $S.CQ.D7
    Check-Alert 'X5' ('Codex ' + $T.H5)       $xr5 $x.H5
    Check-Alert 'X7' ('Codex ' + $T.D7)       $xr7 $x.D7
}

function Check-Alert($id, $name, $remain, $w) {
    if ($null -eq $remain -or -not $w) { return }
    $winId = if ($w.Reset) { $w.Reset.ToUnixTimeSeconds() } else { 0 }
    $hit = $null
    foreach ($t in ($Cfg.Thresholds | Sort-Object -Descending)) {
        if ($remain -le $t) {
            $k = "$id|$winId|$t"
            if (-not $S.Alerted.ContainsKey($k)) { $S.Alerted[$k] = $true; $hit = $t }
        }
    }
    if ($null -ne $hit) {
        $msg = $T.AlertBody -f $remain
        if ($w.Reset) { $msg += ' · ' + (Format-Reset $w.Reset $true) }
        $Tray.ShowBalloonTip(8000, ($T.AlertTitle -f $name), $msg, [System.Windows.Forms.ToolTipIcon]::Warning)
    }
}

# ---------- tray ----------
function New-TrayIcon($argb) {
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($argb))), 1, 1, 30, 30)
    $font = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $g.DrawString('T', $font, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF(0, 0, 32, 32)), $sf)
    $g.Dispose()
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}
$TrayIcons = @{ Green = New-TrayIcon 0xFF2FB350; Amber = New-TrayIcon 0xFFE8900A; Red = New-TrayIcon 0xFFE5392F }
function Set-TrayLevel($lvl) { if ($S.TrayLevel -ne $lvl) { $S.TrayLevel = $lvl; $Tray.Icon = $TrayIcons[$lvl] } }

$Tray = New-Object System.Windows.Forms.NotifyIcon
$Tray.Icon = $TrayIcons.Green
$Tray.Text = $AppName
$Tray.Visible = $true

# autostart = a shortcut in the user's Startup folder (same kind the installer makes)
$StartupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Token Gauge.lnk'
function Test-Autostart { Test-Path -LiteralPath $StartupLnk }
function Set-Autostart([bool]$on) {
    if (-not $on) { Remove-Item -LiteralPath $StartupLnk -ErrorAction SilentlyContinue; return }
    $sh = New-Object -ComObject WScript.Shell
    $lnk = $sh.CreateShortcut($StartupLnk)
    $lnk.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $lnk.Arguments = '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "{0}"' -f $MainScript
    $lnk.WorkingDirectory = $ScriptDir
    $lnk.WindowStyle = 7
    $lnk.Description = $AppName
    $lnk.Save()
}

$Menu = New-Object System.Windows.Forms.ContextMenuStrip
$miShow = $Menu.Items.Add($T.MenuShow)
$miRefresh = $Menu.Items.Add($T.MenuRefresh)
$miTop = New-Object System.Windows.Forms.ToolStripMenuItem($T.MenuTop); [void]$Menu.Items.Add($miTop)
$miAuto = New-Object System.Windows.Forms.ToolStripMenuItem($T.MenuAuto); [void]$Menu.Items.Add($miAuto)
$miFolder = $Menu.Items.Add($T.MenuFolder)
[void]$Menu.Items.Add('-')
$miLang = New-Object System.Windows.Forms.ToolStripMenuItem('Language'); [void]$Menu.Items.Add($miLang)
$LangItems = @{}
foreach ($code in @('auto') + $LangOrder) {
    $it = New-Object System.Windows.Forms.ToolStripMenuItem($code)
    $it.Tag = $code
    $it.Add_Click({ param($sender, $e) Set-Language ([string]$sender.Tag) })
    [void]$miLang.DropDownItems.Add($it)
    $LangItems[$code] = $it
    if ($code -eq 'auto') { [void]$miLang.DropDownItems.Add('-') }
}
$miExit = $Menu.Items.Add($T.MenuExit)
$Tray.ContextMenuStrip = $Menu
$Menu.Add_Opening({
    $miTop.Checked = $win.Topmost; $miAuto.Checked = (Test-Autostart)
    $cur = [string]$Cfg.Language; if (-not $LangItems.ContainsKey($cur)) { $cur = 'auto' }
    foreach ($k in $LangItems.Keys) { $LangItems[$k].Checked = ($k -eq $cur) }
})

# applies $T to every piece of text in the window and the tray menu (live, no restart)
function Apply-Language {
    $font = 'Segoe UI Variable Text, Segoe UI'
    if ($T.Font) { $font += ', ' + $T.Font }
    $win.FontFamily = New-Object System.Windows.Media.FontFamily($font)
    $UI.HeaderText.Text = $T.Header
    $UI.BtnRefresh.ToolTip = $T.TipRefresh; $UI.BtnPin.ToolTip = $T.TipPin; $UI.BtnHide.ToolTip = $T.TipHide
    foreach ($p in 'C','X') {
        $UI["${p}_TodayLbl"].Text = $T.Today
        $UI["${p}_H5_Lbl"].Text = $T.H5
        $UI["${p}_D7_Lbl"].Text = $T.D7
    }
    $miShow.Text = $T.MenuShow; $miRefresh.Text = $T.MenuRefresh; $miTop.Text = $T.MenuTop
    $miAuto.Text = $T.MenuAuto; $miFolder.Text = $T.MenuFolder; $miExit.Text = $T.MenuExit
    $miLang.Text = $(if ($Lang -eq 'en') { 'Language' } else { $T.MenuLang + ' / Language' })
    $LangItems['auto'].Text = $T.LangAuto
    foreach ($code in $LangOrder) { $LangItems[$code].Text = $Strings[$code].Native }
}
function Set-Language([string]$code) {
    $Cfg.Language = $code
    Save-Settings
    $script:Lang = Resolve-Lang $code
    $script:T = $Strings[$script:Lang]
    Apply-Language
    Render
}
Apply-Language

function Toggle-Window { if ($win.IsVisible) { $win.Hide() } else { $win.Show(); [void]$win.Activate() } }
function Set-Topmost([bool]$v) { $win.Topmost = $v; $Cfg.Topmost = $v; $UI.BtnPin.Foreground = $(if ($v) { $Brush.Pin } else { $Brush.Dim }); Save-Settings }
function Refresh-Now { $S.ClaudeDirsAt = $null; $S.NextLocal = [DateTime]::MinValue; $S.NextQuota = [DateTime]::MinValue; Tick }
function Save-Position { $Cfg.Left = $win.Left; $Cfg.Top = $win.Top; Save-Settings }
function Exit-App {
    try { Save-Position } catch {}
    $Tray.Visible = $false; $Tray.Dispose()
    [System.Windows.Application]::Current.Shutdown()
}

$Tray.Add_MouseDoubleClick({ Toggle-Window })
$miShow.Add_Click({ Toggle-Window })
$miRefresh.Add_Click({ Refresh-Now })
$miTop.Add_Click({ Set-Topmost (-not $win.Topmost) })
$miAuto.Add_Click({ try { Set-Autostart (-not (Test-Autostart)) } catch { Log "autostart: $_" } })
$miFolder.Add_Click({ Start-Process explorer.exe $AppDir })
$miExit.Add_Click({ Exit-App })

# ---------- window ----------
$UI.Root.Add_MouseLeftButtonDown({ try { $win.DragMove(); Save-Position } catch {} })
$UI.BtnRefresh.Add_Click({ Refresh-Now })
$UI.BtnPin.Add_Click({ Set-Topmost (-not $win.Topmost) })
$UI.BtnHide.Add_Click({ $win.Hide() })

$wa = [System.Windows.SystemParameters]::WorkArea
$vl = [System.Windows.SystemParameters]::VirtualScreenLeft; $vt = [System.Windows.SystemParameters]::VirtualScreenTop
$vw = [System.Windows.SystemParameters]::VirtualScreenWidth; $vh = [System.Windows.SystemParameters]::VirtualScreenHeight
if ($null -ne $Cfg.Left -and $null -ne $Cfg.Top -and $Cfg.Left -ge $vl -and $Cfg.Left -lt ($vl + $vw - 60) -and $Cfg.Top -ge $vt -and $Cfg.Top -lt ($vt + $vh - 60)) {
    $win.Left = [double]$Cfg.Left; $win.Top = [double]$Cfg.Top
} else {
    $win.Left = $wa.Right - 330; $win.Top = $wa.Top + 12
}
$win.Topmost = [bool]$Cfg.Topmost
$UI.BtnPin.Foreground = $(if ($win.Topmost) { $Brush.Pin } else { $Brush.Dim })

# ---------- main loop ----------
function Tick {
    if ((Get-Date).Date -ne $S.Day) { Reset-Day; $S.NextLocal = [DateTime]::MinValue }
    $now = [DateTime]::UtcNow
    if ($now -ge $S.NextLocal) { Update-Local; $S.NextLocal = $now.AddSeconds([double]$Cfg.LocalRefreshSec) }
    if ($now -ge $S.NextQuota) { Start-ClaudeQuotaFetch; $S.NextQuota = $now.AddSeconds([double]$Cfg.QuotaRefreshSec) }
    Poll-ClaudeQuota
    Render
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({ try { Tick } catch { Log "tick: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" } })

$win.Show()
try { Tick } catch { Log "first tick: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" }
$timer.Start()
[void]$app.Run()
