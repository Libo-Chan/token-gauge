# Token Gauge - desktop widget for Claude Code / Codex token usage and plan quota (Windows)
# https://github.com/Libo-Chan/token-gauge  -  MIT License
# Runs on the built-in Windows PowerShell 5.1 + WPF. Nothing else to install.
# Unofficial. Not affiliated with Anthropic or OpenAI.

$ErrorActionPreference = 'Stop'
$AppName    = 'Token Gauge'
$AppVersion = '0.3.0'
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
$QuotaCachePath = Join-Path $AppDir 'claude-quota.json'

$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
$CodexDir  = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$ClaudeProjects = Join-Path $ClaudeDir 'projects'
$ClaudeCred     = Join-Path $ClaudeDir '.credentials.json'
$CodexRoots     = @((Join-Path $CodexDir 'sessions'), (Join-Path $CodexDir 'archived_sessions'))

function Log($msg) {
    try { Add-Content -LiteralPath $LogPath -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) -Encoding UTF8 } catch {}
}

# Fixed behaviour, not settings: these defaults are right for everyone
$Thresholds      = @(20, 10)   # notify when a limit drops to these % left
$LocalRefreshSec = 15          # rescan local logs
$QuotaRefreshSec = 120         # ask the Claude usage endpoint (be gentle with it)

# Everything that is still a setting is switched from the tray menu; nobody needs to edit settings.json
$Cfg = @{ Left = $null; Top = $null; Topmost = $true; Language = 'auto'; EdgeDock = $true; Dock = $null }
if (Test-Path -LiteralPath $SettingsPath) {
    try {
        $j = [IO.File]::ReadAllText($SettingsPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        foreach ($p in $j.PSObject.Properties) { if ($Cfg.ContainsKey($p.Name)) { $Cfg[$p.Name] = $p.Value } }   # drops keys from older versions
    } catch { Log "settings: $_" }
}
if ($Cfg.Dock) { $d0 = $Cfg.Dock; $Cfg.Dock = @{ Edge = [string]$d0.Edge; Pos = [int]$d0.Pos; Screen = [string]$d0.Screen; Pinned = [bool]$d0.Pinned } }
function Save-Settings {
    try { [IO.File]::WriteAllText($SettingsPath, ($Cfg | ConvertTo-Json), (New-Object Text.UTF8Encoding($false))) } catch { Log "save: $_" }
}

# ---------- strings (add a language: copy the 'en' block, translate, add it to $LangOrder) ----------
$Strings = @{
    'en' = @{
        ClaudeDetail = 'In {0} · Out {1} · Cache {2}'; CodexDetail = 'In {0} (cached {1}) · Out {2}'
        Native = 'English'; Font = ''
        Today = '{0} tokens today'
        H5 = '5-hour limit'; D7 = 'Weekly limit'; H5P = '5-hour limit'; D7P = 'weekly limit'; H5Short = '5-hour'; D7Short = 'Weekly'
        HeroLbl = '{0} left'; SecFmt = '{0}: {1:0}% left · {2}'
        ResetIn = 'resets in {0}'; ResetAt = 'Resets {0}'; ResetNow = 'resetting now'
        Min = '{0} min'; HrMin = '{0}h {1}m'; DaysHours = '{0}d {1}h'
        NoData = 'No data yet'; WindowReset = 'Reset, waiting for new data'; NotStarted = 'Window not started yet'
        PaceOk = "At this pace you'll make it to the reset"
        PaceOut = '{0} runs out in ~{1}, ~{2} before it resets'
        PaceOutSelf = 'Runs out in ~{0}, ~{1} before it resets'
        PaceEmpty = '{0} used up'
        AsOf = 'Data from {0}'; ApproxMin = '{0} min'; ApproxHr = '{0}h'; ApproxDay = '{0}d'
        Fetching = 'Fetching limits…'
        NoCred = 'Sign in to the Claude Code CLI once to see your Claude limits.'
        Expired = 'Login expired. Renewing it automatically; if it does not come back, sign in again.'
        Invalid = 'Login is no longer valid. Please sign in again.'
        Connect = 'Connect Claude account'; Relogin = 'Sign in to Claude again'
        ConnectTip = 'Opens a terminal and runs claude auth login (installs the Claude Code CLI with the official script first if it is missing)'
        ConsoleDone = 'Done. You can close this window.'
        TooMany = 'Limit endpoint rate-limited, retrying later.'
        NetErr = 'Could not reach the limit endpoint, retrying later.'
        NoCodexDir = 'Codex sessions folder not found: {0}'
        NoCodexRecent = 'No Codex activity in the last 7 days. Use Codex once to see the limits.'
        AlertTitle = '{0} running low'; AlertBody = 'Only {0:0}% left'
        TipPin = 'Always on top'; TipHide = 'Hide to tray (double-click the tray icon to restore)'
        TipKeep = 'Keep shown (do not auto-hide at the screen edge)'; MarkerTip = 'Click to show Token Gauge'
        MenuShow = 'Show / hide'; MenuRefresh = 'Refresh now'; MenuTop = 'Always on top'; MenuAuto = 'Start with Windows'; MenuEdge = 'Auto-hide at screen edge'; MenuFolder = 'Open log folder'; MenuExit = 'Exit'
        MenuLang = 'Language'; LangAuto = 'Follow system'
        Tip5h = '{0} 5h: {1:0}% left'
    }
    'zh-CN' = @{
        ClaudeDetail = '输入 {0} · 输出 {1} · 缓存 {2}'; CodexDetail = '输入 {0}（缓存 {1}）· 输出 {2}'
        Native = '简体中文'; Font = 'Microsoft YaHei UI'
        Today = '今日 {0} tokens'
        H5 = '5 小时额度'; D7 = '每周额度'; H5P = '5 小时额度'; D7P = '每周额度'; H5Short = '5 小时'; D7Short = '本周'
        HeroLbl = '{0}剩余'; SecFmt = '{0}剩余 {1:0}% · {2}'
        ResetIn = '{0}后重置'; ResetAt = '重置时间 {0}'; ResetNow = '即将重置'
        Min = '{0} 分钟'; HrMin = '{0} 小时 {1} 分'; DaysHours = '{0} 天 {1} 小时'
        NoData = '暂无数据'; WindowReset = '已重置，等待新数据'; NotStarted = '尚未开始计时'
        PaceOk = '按当前速度，能撑到重置'
        PaceOut = '{0}约 {1}后用完，比重置早约 {2}'
        PaceOutSelf = '约 {0}后用完，比重置早约 {1}'
        PaceEmpty = '{0}已用完'
        AsOf = '数据来自 {0}'; ApproxMin = '{0} 分钟'; ApproxHr = '{0} 小时'; ApproxDay = '{0} 天'
        Fetching = '正在获取额度…'
        NoCred = '登录一次 Claude Code 命令行，就能显示 Claude 额度。'
        Expired = '登录已过期，正在自动续期；一直不恢复的话请重新登录。'
        Invalid = '登录已失效，请重新登录。'
        Connect = '连接 Claude 账号'; Relogin = '重新登录 Claude'
        ConnectTip = '打开终端运行 claude auth login（没装 Claude Code 命令行时，先用官方脚本安装）'
        ConsoleDone = '完成，可以关闭这个窗口了。'
        TooMany = '额度查询过于频繁，稍后自动重试。'
        NetErr = '额度获取失败（网络），稍后自动重试。'
        NoCodexDir = '未找到 Codex 会话目录：{0}'
        NoCodexRecent = '最近 7 天没有 Codex 使用记录，用一次 Codex 后显示额度。'
        AlertTitle = '{0}不足'; AlertBody = '仅剩 {0:0}%'
        TipPin = '窗口置顶'; TipHide = '隐藏到托盘（双击托盘图标恢复）'
        TipKeep = '长期显示（贴边时不自动隐藏）'; MarkerTip = '点击显示 Token Gauge'
        MenuShow = '显示 / 隐藏'; MenuRefresh = '立即刷新'; MenuTop = '窗口置顶'; MenuAuto = '开机自动启动'; MenuEdge = '贴边自动隐藏'; MenuFolder = '打开日志文件夹'; MenuExit = '退出'
        MenuLang = '语言'; LangAuto = '跟随系统'
        Tip5h = '{0} 5h 剩余 {1:0}%'
    }
    'zh-TW' = @{
        ClaudeDetail = '輸入 {0} · 輸出 {1} · 快取 {2}'; CodexDetail = '輸入 {0}（快取 {1}）· 輸出 {2}'
        Native = '繁體中文'; Font = 'Microsoft JhengHei UI'
        Today = '今日 {0} tokens'
        H5 = '5 小時額度'; D7 = '每週額度'; H5P = '5 小時額度'; D7P = '每週額度'; H5Short = '5 小時'; D7Short = '本週'
        HeroLbl = '{0}剩餘'; SecFmt = '{0}剩餘 {1:0}% · {2}'
        ResetIn = '{0}後重置'; ResetAt = '重置時間 {0}'; ResetNow = '即將重置'
        Min = '{0} 分鐘'; HrMin = '{0} 小時 {1} 分'; DaysHours = '{0} 天 {1} 小時'
        NoData = '暫無資料'; WindowReset = '已重置，等待新資料'; NotStarted = '尚未開始計時'
        PaceOk = '照目前速度，可以撐到重置'
        PaceOut = '{0}約 {1}後用完，比重置早約 {2}'
        PaceOutSelf = '約 {0}後用完，比重置早約 {1}'
        PaceEmpty = '{0}已用完'
        AsOf = '資料來自 {0}'; ApproxMin = '{0} 分鐘'; ApproxHr = '{0} 小時'; ApproxDay = '{0} 天'
        Fetching = '正在取得額度…'
        NoCred = '登入一次 Claude Code 命令列版，就能顯示 Claude 額度。'
        Expired = '登入已過期，正在自動續期；若一直未恢復，請重新登入。'
        Invalid = '登入已失效，請重新登入。'
        Connect = '連結 Claude 帳號'; Relogin = '重新登入 Claude'
        ConnectTip = '開啟終端機執行 claude auth login（未安裝 Claude Code 命令列版時，先用官方指令碼安裝）'
        ConsoleDone = '完成，可以關閉這個視窗了。'
        TooMany = '額度查詢過於頻繁，稍後自動重試。'
        NetErr = '無法取得額度（網路問題），稍後自動重試。'
        NoCodexDir = '找不到 Codex 工作階段資料夾：{0}'
        NoCodexRecent = '最近 7 天沒有 Codex 使用紀錄，使用一次 Codex 後即會顯示額度。'
        AlertTitle = '{0}即將用完'; AlertBody = '僅剩 {0:0}%'
        TipPin = '視窗置頂'; TipHide = '隱藏到系統匣（按兩下系統匣圖示即可還原）'
        TipKeep = '長期顯示（貼邊時不自動隱藏）'; MarkerTip = '按一下以顯示 Token Gauge'
        MenuShow = '顯示 / 隱藏'; MenuRefresh = '立即重新整理'; MenuTop = '視窗置頂'; MenuAuto = '開機時自動啟動'; MenuEdge = '貼邊自動隱藏'; MenuFolder = '開啟記錄資料夾'; MenuExit = '結束'
        MenuLang = '語言'; LangAuto = '跟隨系統'
        Tip5h = '{0} 5h 剩餘 {1:0}%'
    }
    'ja' = @{
        ClaudeDetail = '入力 {0} · 出力 {1} · キャッシュ {2}'; CodexDetail = '入力 {0}（キャッシュ {1}）· 出力 {2}'
        Native = '日本語'; Font = 'Yu Gothic UI'
        Today = '本日 {0} トークン'
        H5 = '5 時間の上限'; D7 = '週間の上限'; H5P = '5 時間の上限'; D7P = '週間の上限'; H5Short = '5 時間'; D7Short = '今週'
        HeroLbl = '{0} 残り'; SecFmt = '{0} 残り {1:0}% · {2}'
        ResetIn = 'あと {0} でリセット'; ResetAt = 'リセット {0}'; ResetNow = 'まもなくリセット'
        Min = '{0} 分'; HrMin = '{0} 時間 {1} 分'; DaysHours = '{0} 日 {1} 時間'
        NoData = 'データなし'; WindowReset = 'リセット済み。新しいデータを待っています'; NotStarted = '期間はまだ始まっていません'
        PaceOk = 'このペースならリセットまで持ちます'
        PaceOut = '{0}は約 {1}で使い切り（リセットの約 {2}前）'
        PaceOutSelf = '約 {0}で使い切り（リセットの約 {1}前）'
        PaceEmpty = '{0}を使い切りました'
        AsOf = '{0} 時点のデータ'; ApproxMin = '{0} 分'; ApproxHr = '{0} 時間'; ApproxDay = '{0} 日'
        Fetching = '上限を取得中…'
        NoCred = 'Claude Code CLI に一度ログインすると、Claude の上限が表示されます。'
        Expired = 'ログインの有効期限が切れました。自動で更新中です。戻らない場合は再ログインしてください。'
        Invalid = 'ログインが無効になりました。再ログインしてください。'
        Connect = 'Claude アカウントを接続'; Relogin = 'Claude に再ログイン'
        ConnectTip = 'ターミナルで claude auth login を実行します（Claude Code CLI がない場合は、公式スクリプトで先にインストール）'
        ConsoleDone = '完了しました。このウィンドウは閉じてかまいません。'
        TooMany = '問い合わせが多すぎます。しばらくして自動で再試行します。'
        NetErr = '上限を取得できませんでした（ネットワーク）。しばらくして自動で再試行します。'
        NoCodexDir = 'Codex のセッションフォルダーが見つかりません: {0}'
        NoCodexRecent = '過去 7 日間 Codex の使用履歴がありません。一度 Codex を使うと上限が表示されます。'
        AlertTitle = '{0}が残りわずか'; AlertBody = '残り {0:0}%'
        TipPin = '常に手前に表示'; TipHide = 'トレイに隠す（トレイアイコンをダブルクリックで再表示）'
        TipKeep = '常に表示（画面の端で自動的に隠さない）'; MarkerTip = 'クリックして Token Gauge を表示'
        MenuShow = '表示 / 非表示'; MenuRefresh = '今すぐ更新'; MenuTop = '常に手前に表示'; MenuAuto = 'Windows 起動時に開始'; MenuEdge = '画面の端で自動的に隠す'; MenuFolder = 'ログフォルダーを開く'; MenuExit = '終了'
        MenuLang = '言語'; LangAuto = 'システムに合わせる'
        Tip5h = '{0} 5h 残り {1:0}%'
    }
    'ko' = @{
        ClaudeDetail = '입력 {0} · 출력 {1} · 캐시 {2}'; CodexDetail = '입력 {0} (캐시 {1}) · 출력 {2}'
        Native = '한국어'; Font = 'Malgun Gothic'
        Today = '오늘 {0} 토큰'
        H5 = '5시간 한도'; D7 = '주간 한도'; H5P = '5시간 한도'; D7P = '주간 한도'; H5Short = '5시간'; D7Short = '이번 주'
        HeroLbl = '{0} 남음'; SecFmt = '{0} {1:0}% 남음 · {2}'
        ResetIn = '{0} 후 초기화'; ResetAt = '초기화 시각 {0}'; ResetNow = '곧 초기화'
        Min = '{0}분'; HrMin = '{0}시간 {1}분'; DaysHours = '{0}일 {1}시간'
        NoData = '데이터 없음'; WindowReset = '초기화됨, 새 데이터 대기 중'; NotStarted = '아직 기간이 시작되지 않음'
        PaceOk = '이 속도라면 초기화까지 충분합니다'
        PaceOut = '{0}는 약 {1} 후 소진 (초기화 약 {2} 전)'
        PaceOutSelf = '약 {0} 후 소진 (초기화 약 {1} 전)'
        PaceEmpty = '{0} 소진'
        AsOf = '{0} 기준 데이터'; ApproxMin = '{0}분'; ApproxHr = '{0}시간'; ApproxDay = '{0}일'
        Fetching = '한도 가져오는 중…'
        NoCred = 'Claude Code CLI에 한 번 로그인하면 Claude 한도가 표시됩니다.'
        Expired = '로그인이 만료되었습니다. 자동으로 갱신 중이며, 계속 안 되면 다시 로그인하세요.'
        Invalid = '로그인이 더 이상 유효하지 않습니다. 다시 로그인하세요.'
        Connect = 'Claude 계정 연결'; Relogin = 'Claude 다시 로그인'
        ConnectTip = '터미널에서 claude auth login을 실행합니다(Claude Code CLI가 없으면 공식 스크립트로 먼저 설치)'
        ConsoleDone = '완료되었습니다. 이 창은 닫아도 됩니다.'
        TooMany = '요청이 너무 많습니다. 잠시 후 자동으로 다시 시도합니다.'
        NetErr = '한도를 가져오지 못했습니다(네트워크). 잠시 후 자동으로 다시 시도합니다.'
        NoCodexDir = 'Codex 세션 폴더를 찾을 수 없습니다: {0}'
        NoCodexRecent = '최근 7일간 Codex 사용 기록이 없습니다. Codex를 한 번 사용하면 한도가 표시됩니다.'
        AlertTitle = '{0} 부족'; AlertBody = '{0:0}%만 남음'
        TipPin = '항상 위에 표시'; TipHide = '트레이로 숨기기(트레이 아이콘을 두 번 클릭하면 복원)'
        TipKeep = '항상 표시 (화면 가장자리에서 자동으로 숨기지 않음)'; MarkerTip = '클릭하여 Token Gauge 표시'
        MenuShow = '표시 / 숨기기'; MenuRefresh = '지금 새로 고침'; MenuTop = '항상 위에 표시'; MenuAuto = 'Windows 시작 시 실행'; MenuEdge = '화면 가장자리에서 자동 숨기기'; MenuFolder = '로그 폴더 열기'; MenuExit = '종료'
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
    CQ = @{ H5 = $null; D7 = $null; Plan = ''; Msg = 'Fetching'; AsOf = $null }   # Msg holds a key into $T
    ClaudeDirs = $null; ClaudeDirsAt = $null
    CliAt = $null
    CredStamp = $null
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
    # take the length from the open stream: while another program keeps the file open, Windows can report a
    # stale size and last-write time for it, so neither is trusted
    $fs = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        $len = $fs.Length
        if ($len -lt $st.Offset) { $st.Offset = [long]0 }
        if ($len -eq $st.Offset) { return ,@() }
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
        foreach ($f in (Get-JsonlFiles $dir $S.Day.AddDays(-2))) {
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
    $len = if ($w.window_minutes) { [double]$w.window_minutes } else { $null }
    return @{ Used = [double]$w.used_percent; Reset = $reset; Len = $len }
}

function Update-Codex {
    # A Codex session can run across midnight and keeps its log open, and Windows may not update the
    # last-write time of an open file. So read every session touched in the last 3 days and decide
    # what counts as "today" from each entry's own timestamp.
    $files = New-Object System.Collections.Generic.List[string]
    $newest = $null; $newestT = [datetime]::MinValue
    foreach ($root in $CodexRoots) {
        if (-not [IO.Directory]::Exists($root)) { continue }
        $S.Codex.Found = $true
        foreach ($f in (Get-JsonlFiles $root $S.Day.AddDays(-7))) {
            $t = [IO.File]::GetLastWriteTime($f)
            if ($t -ge $S.Day.AddDays(-3)) { $files.Add($f) }
            if ($t -gt $newestT) { $newestT = $t; $newest = $f }
        }
    }
    if ($files.Count -eq 0 -and $newest) { $files.Add($newest) }   # idle for days: still show the last known limits
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
    param($credPath, $ua, $allowCli)
    $out = @{ ok = $false; err = ''; code = 0; plan = ''; data = $null; cliRan = $false }

    # The login token in .credentials.json only lasts a few hours; Claude Code renews it whenever it runs.
    # `claude auth status` is enough to make it do that, and it uses no quota. Token Gauge itself never
    # writes the token: it only asks the official CLI to refresh it, then reads it again.
    function Find-ClaudeCli {
        $c = Get-Command claude.exe, claude.cmd, claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($c) { return $c.Source }
        foreach ($p in @((Join-Path $env:USERPROFILE '.local\bin\claude.exe'), (Join-Path $env:APPDATA 'npm\claude.cmd'))) { if (Test-Path -LiteralPath $p) { return $p } }
        return $null
    }
    function Invoke-ClaudeAuthStatus {
        $exe = Find-ClaudeCli
        if (-not $exe) { return $false }
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        if ($exe -like '*.cmd') { $psi.FileName = $env:ComSpec; $psi.Arguments = '/d /c ""{0}" auth status"' -f $exe }
        else { $psi.FileName = $exe; $psi.Arguments = 'auth status' }
        $psi.WorkingDirectory = $env:USERPROFILE
        # Run it in a hidden console and do NOT redirect its output: with redirected output the CLI sees
        # no terminal, just prints its status as JSON and skips renewing the token.
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $proc = [Diagnostics.Process]::Start($psi)
        if (-not $proc.WaitForExit(45000)) { try { $proc.Kill() } catch {}; return $false }
        return $true
    }
    function Read-Token { ([IO.File]::ReadAllText($credPath, [Text.Encoding]::UTF8) | ConvertFrom-Json).claudeAiOauth }
    function Test-ExpiringSoon($o) { $o.expiresAt -and ([DateTimeOffset]::FromUnixTimeMilliseconds([long]$o.expiresAt) -lt [DateTimeOffset]::UtcNow.AddMinutes(5)) }
    function Get-Usage($o) {
        $h = @{ 'Authorization' = "Bearer $($o.accessToken)"; 'anthropic-beta' = 'oauth-2025-04-20'; 'Accept' = 'application/json' }
        Invoke-RestMethod -Uri 'https://api.anthropic.com/api/oauth/usage' -Headers $h -Method Get -TimeoutSec 20 -UseBasicParsing -UserAgent $ua
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        if (-not (Test-Path -LiteralPath $credPath)) { $out.err = 'nocred'; return $out }
        $o = Read-Token
        if (-not $o -or -not $o.accessToken) { $out.err = 'nocred'; return $out }
        $out.plan = [string]$o.subscriptionType
        if ((Test-ExpiringSoon $o) -and $allowCli) {
            $out.cliRan = $true
            if (Invoke-ClaudeAuthStatus) { $o = Read-Token }
        }
        if ($o.expiresAt -and [DateTimeOffset]::FromUnixTimeMilliseconds([long]$o.expiresAt) -lt [DateTimeOffset]::UtcNow) { $out.err = 'expired'; return $out }
        try { $out.data = Get-Usage $o }
        catch {
            $code = 0; try { $code = [int]$_.Exception.Response.StatusCode } catch {}
            if ($code -eq 401 -and $allowCli -and -not $out.cliRan) {
                $out.cliRan = $true
                if (Invoke-ClaudeAuthStatus) { $o = Read-Token; $out.data = Get-Usage $o } else { throw }
            } else { throw }
        }
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
    $allowCli = ($null -eq $S.CliAt -or ([DateTime]::UtcNow - $S.CliAt).TotalMinutes -ge 10)   # at most one CLI run per 10 minutes
    [void]$ps.AddScript($FetchScript).AddArgument($ClaudeCred).AddArgument("TokenGauge/$AppVersion").AddArgument($allowCli)
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
$ClaudeLen = @{ H5 = 300.0; D7 = 10080.0 }   # Claude does not report its window lengths: 5 hours and 7 days

# last successful Claude quota, so the bars survive a restart or an expired token
function Save-QuotaCache {
    try {
        $o = @{ AsOf = $S.CQ.AsOf.ToString('o'); Plan = $S.CQ.Plan }
        foreach ($k in 'H5','D7') { $w = $S.CQ[$k]; if ($w) { $o[$k] = @{ Used = $w.Used; Reset = $(if ($w.Reset) { $w.Reset.ToUnixTimeSeconds() } else { $null }) } } }
        [IO.File]::WriteAllText($QuotaCachePath, ($o | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
    } catch { Log "quota cache save: $_" }
}
function Load-QuotaCache {
    try {
        if (-not (Test-Path -LiteralPath $QuotaCachePath)) { return }
        $o = [IO.File]::ReadAllText($QuotaCachePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        foreach ($k in 'H5','D7') {
            $w = $o.$k
            if ($w) { $S.CQ[$k] = @{ Used = [double]$w.Used; Reset = $(if ($w.Reset) { [DateTimeOffset]::FromUnixTimeSeconds([long]$w.Reset) } else { $null }) } }
        }
        if ($o.Plan) { $S.CQ.Plan = [string]$o.Plan }
        if ($o.AsOf -is [datetime]) { $S.CQ.AsOf = $o.AsOf.ToLocalTime() } elseif ($o.AsOf) { $S.CQ.AsOf = [datetime]::Parse([string]$o.AsOf, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToLocalTime() }
    } catch { Log "quota cache load: $_" }
}

function Poll-ClaudeQuota {
    if (-not $S.Http -or -not $S.Http.H.IsCompleted) { return }
    $res = $null
    try { $r = $S.Http.PS.EndInvoke($S.Http.H); if ($r.Count -gt 0) { $res = $r[$r.Count - 1] } } catch { Log "fetch end: $_" }
    try { $S.Http.PS.Dispose(); $S.Http.RS.Dispose() } catch {}
    $S.Http = $null
    if (-not $res) { return }
    if ($res.cliRan) { $S.CliAt = [DateTime]::UtcNow }
    if ($res.plan) { $S.CQ.Plan = $res.plan }
    if ($res.ok) {
        $S.CQ.H5 = Convert-ClaudeWindow $res.data.five_hour
        $S.CQ.D7 = Convert-ClaudeWindow $res.data.seven_day
        $S.CQ.Msg = ''
        $S.CQ.AsOf = Get-Date
        Save-QuotaCache
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
  <Grid Margin="0,2,0,0">
    <TextBlock x:Name="P_Hero" Text="—" FontSize="32" FontWeight="SemiBold" Foreground="#80FFFFFF" VerticalAlignment="Center"/>
    <StackPanel HorizontalAlignment="Right" VerticalAlignment="Center">
      <TextBlock x:Name="P_HeroLbl" Style="{StaticResource Small}" Foreground="#CCFFFFFF" HorizontalAlignment="Right" Text=" "/>
      <TextBlock x:Name="P_HeroReset" Style="{StaticResource Small}" HorizontalAlignment="Right" Text=" " Margin="0,2,0,0"/>
    </StackPanel>
  </Grid>
  <Grid x:Name="P_Bar" Height="6" Margin="0,4,0,0">
    <Grid.ColumnDefinitions><ColumnDefinition Width="0*"/><ColumnDefinition Width="1*"/></Grid.ColumnDefinitions>
    <Border Grid.ColumnSpan="2" CornerRadius="3" Background="#1FFFFFFF"/>
    <Border x:Name="P_Fill" Grid.Column="0" CornerRadius="3" Background="#FF34C759"/>
  </Grid>
  <TextBlock x:Name="P_Pace" FontSize="11" TextWrapping="Wrap" Margin="0,7,0,0" Visibility="Collapsed"/>
  <StackPanel x:Name="P_SecBox" Margin="0,9,0,0">
    <TextBlock x:Name="P_Sec" Style="{StaticResource Small}" TextWrapping="Wrap" Text=" "/>
    <Grid x:Name="P_Bar2" Height="3" Margin="0,4,0,0">
      <Grid.ColumnDefinitions><ColumnDefinition Width="0*"/><ColumnDefinition Width="1*"/></Grid.ColumnDefinitions>
      <Border Grid.ColumnSpan="2" CornerRadius="1.5" Background="#1FFFFFFF"/>
      <Border x:Name="P_Fill2" Grid.Column="0" CornerRadius="1.5" Background="#FF34C759"/>
    </Grid>
  </StackPanel>
  <TextBlock x:Name="P_Today" Style="{StaticResource Small}" Foreground="#66FFFFFF" Margin="0,8,0,0" Visibility="Collapsed"/>
  <TextBlock x:Name="P_Msg" FontSize="11" Foreground="#8CFFFFFF" TextWrapping="Wrap" Visibility="Collapsed" Margin="0,8,0,0"/>
  <Button x:Name="P_Connect" Style="{StaticResource PillBtn}" HorizontalAlignment="Left" Margin="0,8,0,0" Visibility="Collapsed"/>
</StackPanel>
'@
function New-Section($prefix, $title, $accent) {
    return $SectionXaml.Replace('P_', "${prefix}_").Replace('TITLE', $title).Replace('ACCENT', $accent)
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
    <Style x:Key="PillBtn" TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="#FFE0875F" CornerRadius="7" Padding="12,5,12,6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="#FFEC9A75"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border x:Name="Root" Margin="12" CornerRadius="14" Background="#F51B1D22" BorderBrush="#22FFFFFF" BorderThickness="1" Padding="16,10,16,16">
    <Border.Effect><DropShadowEffect BlurRadius="16" ShadowDepth="2" Opacity="0.4"/></Border.Effect>
    <StackPanel>
      <Grid>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="BtnKeep" Style="{StaticResource IconBtn}" Content="&#xE890;" Visibility="Collapsed"/>
          <Button x:Name="BtnPin" Style="{StaticResource IconBtn}" Content="&#xE718;"/>
          <Button x:Name="BtnHide" Style="{StaticResource IconBtn}" Content="&#xE921;"/>
        </StackPanel>
      </Grid>
      SECTION_CLAUDE
      <Border Height="1" Background="#14FFFFFF" Margin="0,14,0,0"/>
      SECTION_CODEX
    </StackPanel>
  </Border>
</Window>
'@
$WindowXaml = $WindowXaml.Replace('SECTION_CLAUDE', (New-Section 'C' 'Claude Code' '#FFE0875F')).Replace('SECTION_CODEX', (New-Section 'X' 'Codex' '#FF6E8BFF'))
$app = New-Object System.Windows.Application
$app.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
$win = [Windows.Markup.XamlReader]::Parse($WindowXaml)

$UI = @{}
foreach ($n in 'Root','BtnKeep','BtnPin','BtnHide') { $UI[$n] = $win.FindName($n) }
foreach ($p in 'C','X') {
    foreach ($n in 'Plan','Hero','HeroLbl','HeroReset','Bar','Fill','Pace','SecBox','Sec','Bar2','Fill2','Today','Msg','Connect') { $UI["${p}_$n"] = $win.FindName("${p}_$n") }
}

$BC = New-Object System.Windows.Media.BrushConverter
$Brush = @{ Green = $BC.ConvertFromString('#FF34C759'); Amber = $BC.ConvertFromString('#FFFF9F0A'); Red = $BC.ConvertFromString('#FFFF453A'); Dim = $BC.ConvertFromString('#80FFFFFF'); Pin = $BC.ConvertFromString('#FFFFB340'); Ok = $BC.ConvertFromString('#B334C759') }
function Get-Level([double]$remain) { if ($remain -le 20) { 'Red' } elseif ($remain -le 50) { 'Amber' } else { 'Green' } }

function Format-Tokens([long]$n) {
    $ci = [Globalization.CultureInfo]::InvariantCulture
    if ($n -ge 1e9) { return ($n / 1e9).ToString('0.00', $ci) + 'B' }
    if ($n -ge 1e6) { return ($n / 1e6).ToString('0.00', $ci) + 'M' }
    if ($n -ge 1e4) { return ($n / 1e3).ToString('0.0', $ci) + 'K' }
    return $n.ToString('N0', $ci)
}
# a duration in words, no seconds: "35 min", "4h 24m", "5d 23h"
function Format-Span([TimeSpan]$s) {
    if ($s.TotalMinutes -lt 1) { $s = [TimeSpan]::FromMinutes(1) }
    if ($s.TotalDays -ge 1) { return $T.DaysHours -f [int][Math]::Floor($s.TotalDays), $s.Hours }
    if ($s.TotalHours -ge 1) { return $T.HrMin -f [int][Math]::Floor($s.TotalHours), $s.Minutes }
    return $T.Min -f [int][Math]::Ceiling($s.TotalMinutes)
}
# an estimate in rounded words: under an hour to 5 minutes, under a day to half an hour, else to half a day
function Format-Approx([TimeSpan]$s) {
    $ci = [Globalization.CultureInfo]::InvariantCulture
    $m = $s.TotalMinutes
    if ($m -lt 55) { return $T.ApproxMin -f [int]([Math]::Max(5, [Math]::Round($m / 5) * 5)) }
    if ($s.TotalHours -lt 23.75) { return $T.ApproxHr -f ([Math]::Max(1, [Math]::Round($s.TotalHours * 2) / 2)).ToString('0.#', $ci) }
    return $T.ApproxDay -f ([Math]::Round($s.TotalDays * 2) / 2).ToString('0.#', $ci)
}
function Set-BarWidth($bar, [double]$remain) {
    $bar.ColumnDefinitions[0].Width = New-Object System.Windows.GridLength($remain, 'Star')
    $bar.ColumnDefinitions[1].Width = New-Object System.Windows.GridLength((100 - $remain), 'Star')
}

# one quota window as shown: remaining %, reset, and the window length for the pace estimate
function Get-View($w, $len, [string]$name, [string]$pname, [string]$short) {
    if (-not $w) { return $null }
    $used = $w.Used
    $expired = [bool]($w.Reset -and $w.Reset -le [DateTimeOffset]::Now)
    if ($expired) { $used = 0 }
    $remain = [Math]::Max(0, [Math]::Min(100, 100 - $used))
    return @{ Remain = $remain; Used = $used; Reset = $w.Reset; Expired = $expired; Len = $len; Name = $name; PName = $pname; Short = $short; W = $w }
}
function Get-ResetText($v) {
    if ($v.Expired) { return $T.WindowReset }
    if (-not $v.Reset) { return $T.NotStarted }
    $span = $v.Reset - [DateTimeOffset]::Now
    if ($span.TotalSeconds -le 0) { return $T.ResetNow }
    return $T.ResetIn -f (Format-Span $span)
}
function Get-ResetTip($v) {
    if (-not $v -or -not $v.Reset -or $v.Expired) { return $null }
    return $T.ResetAt -f $v.Reset.LocalDateTime.ToString('M/d HH:mm')
}

# Will this window last until it resets? Uses the average rate since the window started, which for
# a long window also allows for the hours you are not working. $null = too early to say.
function Get-Pace($v) {
    if (-not $v -or $v.Expired -or -not $v.Reset -or -not $v.Len) { return $null }
    $now = [DateTimeOffset]::Now
    if ($v.Remain -le 0) { return @{ Empty = $true; V = $v } }
    $elapsed = ($now - $v.Reset.AddMinutes(-$v.Len)).TotalMinutes
    if ($elapsed -lt [Math]::Max(15, $v.Len * 0.05)) { return $null }   # 5h: after 15 min, weekly: after ~8 h
    if ($v.Used -le 0) { return @{ Out = $false; V = $v } }
    $emptyAt = $now.AddMinutes($v.Remain / ($v.Used / $elapsed))
    if ($emptyAt -ge $v.Reset) { return @{ Out = $false; V = $v } }
    return @{ Out = $true; V = $v; In = ($emptyAt - $now); Early = ($v.Reset - $emptyAt); At = $emptyAt }
}

# draws one service: the tighter of its two limits is the big number, the other one sits below it
function Set-Section([string]$p, $h5, $d7, [long]$today, [string]$detail) {
    $views = @(@($h5, $d7) | Where-Object { $_ })
    $hero = $null; $sec = $null
    if ($views.Count -gt 0) {
        $hero = $views[0]
        foreach ($v in $views) { if ($v.Remain -lt $hero.Remain) { $hero = $v } }
        foreach ($v in $views) { if (-not [object]::ReferenceEquals($v, $hero)) { $sec = $v } }
    }
    $big = $UI["${p}_Hero"]
    if ($hero) {
        $lvl = Get-Level $hero.Remain
        $big.Text = '{0:0}%' -f $hero.Remain; $big.Foreground = $Brush[$lvl]
        $UI["${p}_HeroLbl"].Text = $T.HeroLbl -f $hero.Name
        $UI["${p}_HeroReset"].Text = Get-ResetText $hero
        $UI["${p}_HeroReset"].ToolTip = Get-ResetTip $hero
        $UI["${p}_Fill"].Background = $Brush[$lvl]
        Set-BarWidth $UI["${p}_Bar"] $hero.Remain
    } else {
        $big.Text = '—'; $big.Foreground = $Brush.Dim
        $UI["${p}_HeroLbl"].Text = $T.NoData; $UI["${p}_HeroReset"].Text = ' '; $UI["${p}_HeroReset"].ToolTip = $null
        Set-BarWidth $UI["${p}_Bar"] 0
    }
    if ($sec) {
        $UI["${p}_SecBox"].Visibility = 'Visible'
        $UI["${p}_Sec"].Text = $T.SecFmt -f $sec.Short, $sec.Remain, (Get-ResetText $sec)
        $UI["${p}_Sec"].ToolTip = Get-ResetTip $sec
        $UI["${p}_Fill2"].Background = $Brush[(Get-Level $sec.Remain)]
        Set-BarWidth $UI["${p}_Bar2"] $sec.Remain
    } else { $UI["${p}_SecBox"].Visibility = 'Collapsed' }

    # pace: warn about the window that runs out first; otherwise say both will last
    $pace = $UI["${p}_Pace"]
    $pc = @($views | ForEach-Object { Get-Pace $_ } | Where-Object { $_ })
    $empty = $pc | Where-Object { $_.Empty } | Select-Object -First 1
    $out = $pc | Where-Object { $_.Out } | Sort-Object { $_.At } | Select-Object -First 1
    if ($empty) {
        $pace.Text = $T.PaceEmpty -f $empty.V.Name; $pace.Foreground = $Brush.Red; $pace.Visibility = 'Visible'
    } elseif ($out) {
        # the big number's own limit needs no name: it is written right above
        if ([object]::ReferenceEquals($out.V, $hero)) { $pace.Text = $T.PaceOutSelf -f (Format-Approx $out.In), (Format-Approx $out.Early) }
        else { $pace.Text = $T.PaceOut -f $out.V.Name, (Format-Approx $out.In), (Format-Approx $out.Early) }
        $pace.Foreground = $(if ($out.In.TotalMinutes -le 30) { $Brush.Red } else { $Brush.Amber }); $pace.Visibility = 'Visible'
    } elseif ($pc.Count -gt 0) {
        $pace.Text = $T.PaceOk; $pace.Foreground = $Brush.Ok; $pace.Visibility = 'Visible'
    } else { $pace.Visibility = 'Collapsed' }

    # today's tokens: a quiet line, details on hover, nothing at all when there is nothing to count
    $td = $UI["${p}_Today"]
    if ($today -gt 0) { $td.Text = $T.Today -f (Format-Tokens $today); $td.ToolTip = $detail; $td.Visibility = 'Visible' }
    else { $td.Visibility = 'Collapsed' }
}

function Plan-Name([string]$p) { if (-not $p) { return '—' }; return $p.Substring(0,1).ToUpper() + $p.Substring(1) }

function Render {
    $c = $S.Claude
    $UI.C_Plan.Text = Plan-Name $S.CQ.Plan
    $c5 = Get-View $S.CQ.H5 $ClaudeLen.H5 $T.H5 $T.H5P $T.H5Short
    $c7 = Get-View $S.CQ.D7 $ClaudeLen.D7 $T.D7 $T.D7P $T.D7Short
    Set-Section 'C' $c5 $c7 ($c.In + $c.Out + $c.CW + $c.CR) ($T.ClaudeDetail -f (Format-Tokens $c.In), (Format-Tokens $c.Out), (Format-Tokens ($c.CW + $c.CR)))
    $cmsg = if ($S.CQ.Msg) { $T[$S.CQ.Msg] } else { '' }
    if ($cmsg -and $S.CQ.Msg -ne 'Fetching' -and $S.CQ.AsOf -and ($S.CQ.H5 -or $S.CQ.D7)) { $cmsg += "`n" + ($T.AsOf -f $S.CQ.AsOf.ToString('M/d HH:mm')) }
    if ($cmsg) { $UI.C_Msg.Text = $cmsg; $UI.C_Msg.Visibility = 'Visible' } else { $UI.C_Msg.Visibility = 'Collapsed' }
    # first run (or a login that has really ended): offer to sign in right here instead of pointing at the README
    if (@('NoCred', 'Expired', 'Invalid') -contains $S.CQ.Msg) {
        $UI.C_Connect.Content = $(if ($S.CQ.Msg -eq 'NoCred') { $T.Connect } else { $T.Relogin })
        $UI.C_Connect.Visibility = 'Visible'
    } else { $UI.C_Connect.Visibility = 'Collapsed' }

    $x = $S.Codex
    $UI.X_Plan.Text = Plan-Name $x.Plan
    $x5 = Get-View $x.H5 $(if ($x.H5) { $x.H5.Len }) $T.H5 $T.H5P $T.H5Short
    $x7 = Get-View $x.D7 $(if ($x.D7) { $x.D7.Len }) $T.D7 $T.D7P $T.D7Short
    Set-Section 'X' $x5 $x7 $x.Total ($T.CodexDetail -f (Format-Tokens $x.In), (Format-Tokens $x.Cached), (Format-Tokens $x.Out))
    if (-not $x.Found) { $UI.X_Msg.Text = $T.NoCodexDir -f $CodexDir; $UI.X_Msg.Visibility = 'Visible' }
    elseif (-not $x.H5) { $UI.X_Msg.Text = $T.NoCodexRecent; $UI.X_Msg.Visibility = 'Visible' }
    else { $UI.X_Msg.Visibility = 'Collapsed' }

    $worst = $null
    foreach ($v in @($c5, $c7, $x5, $x7)) { if ($v -and ($null -eq $worst -or $v.Remain -lt $worst)) { $worst = $v.Remain } }
    Set-TrayLevel (Get-Level $(if ($null -eq $worst) { 100 } else { $worst }))
    if ($MarkerNum) {
        foreach ($k in 'C','X') {
            $pair = if ($k -eq 'C') { @($c5, $c7) } else { @($x5, $x7) }
            $m = $null; foreach ($v in $pair) { if ($v -and ($null -eq $m -or $v.Remain -lt $m)) { $m = $v.Remain } }
            if ($null -eq $m) { $MarkerNum[$k].Text = '—'; $MarkerNum[$k].Foreground = $Brush.Dim }
            else { $MarkerNum[$k].Text = '{0:0}' -f $m; $MarkerNum[$k].Foreground = $Brush[(Get-Level $m)] }
        }
    }
    $tip = $AppName
    if ($c5) { $tip += "`n" + ($T.Tip5h -f 'Claude', $c5.Remain) }
    if ($x5) { $tip += "`n" + ($T.Tip5h -f 'Codex', $x5.Remain) }
    if ($tip.Length -gt 63) { $tip = $tip.Substring(0, 63) }
    $Tray.Text = $tip

    foreach ($a in @(@('C5', 'Claude Code', $c5), @('C7', 'Claude Code', $c7), @('X5', 'Codex', $x5), @('X7', 'Codex', $x7))) {
        if ($a[2]) { Check-Alert $a[0] ($a[1] + ' ' + $a[2].Name) $a[2] }
    }
}

function Check-Alert($id, $name, $v) {
    $winId = if ($v.Reset) { $v.Reset.ToUnixTimeSeconds() } else { 0 }
    $hit = $null
    foreach ($t in ($Thresholds | Sort-Object -Descending)) {
        if ($v.Remain -le $t) {
            $k = "$id|$winId|$t"
            if (-not $S.Alerted.ContainsKey($k)) { $S.Alerted[$k] = $true; $hit = $t }
        }
    }
    if ($null -ne $hit) {
        $msg = $T.AlertBody -f $v.Remain
        if ($v.Reset -and -not $v.Expired) { $msg += ' · ' + (Get-ResetText $v) }
        $Tray.ShowBalloonTip(8000, ($T.AlertTitle -f $name), $msg, [System.Windows.Forms.ToolTipIcon]::Warning)
    }
}

# ---------- Claude sign-in from the widget ----------
function Find-ClaudeCliMain {
    $c = Get-Command claude.exe, claude.cmd, claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source }
    foreach ($p in @((Join-Path $env:USERPROFILE '.local\bin\claude.exe'), (Join-Path $env:APPDATA 'npm\claude.cmd'))) { if (Test-Path -LiteralPath $p) { return $p } }
    return $null
}
# Opens a normal PowerShell window that signs in with the official CLI (installing it with the official
# script first if it is missing). The widget notices the new login file by itself and fetches the limits.
function Start-ClaudeLogin {
    $exe = Find-ClaudeCliMain
    $done = "Write-Host ''; Write-Host '" + $T.ConsoleDone.Replace("'", "''") + "'"
    if ($exe) { $cmd = "& '" + $exe.Replace("'", "''") + "' auth login; " + $done }
    else { $cmd = 'irm https://claude.ai/install.ps1 | iex; $env:Path += '';'' + (Join-Path $env:USERPROFILE ''.local\bin''); claude auth login; ' + $done }
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))   # no quoting problems with paths or non-ASCII text
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-NoExit', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc) -WorkingDirectory $env:USERPROFILE
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
function Set-TrayLevel($lvl) { if ($S.TrayLevel -ne $lvl) { $S.TrayLevel = $lvl; $Tray.Icon = $TrayIcons[$lvl]; } }

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
$miEdge = New-Object System.Windows.Forms.ToolStripMenuItem($T.MenuEdge); [void]$Menu.Items.Add($miEdge)
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
    $miTop.Checked = [bool]$Cfg.Topmost; $miAuto.Checked = (Test-Autostart); $miEdge.Checked = [bool]$Cfg.EdgeDock
    $cur = [string]$Cfg.Language; if (-not $LangItems.ContainsKey($cur)) { $cur = 'auto' }
    foreach ($k in $LangItems.Keys) { $LangItems[$k].Checked = ($k -eq $cur) }
})

# applies $T to every piece of text in the window and the tray menu (live, no restart)
function Apply-Language {
    $font = 'Segoe UI Variable Text, Segoe UI'
    if ($T.Font) { $font += ', ' + $T.Font }
    $win.FontFamily = New-Object System.Windows.Media.FontFamily($font)
    $UI.BtnPin.ToolTip = $T.TipPin; $UI.BtnHide.ToolTip = $T.TipHide; $UI.BtnKeep.ToolTip = $T.TipKeep
    $UI.C_Connect.ToolTip = $T.ConnectTip
    $miShow.Text = $T.MenuShow; $miRefresh.Text = $T.MenuRefresh; $miTop.Text = $T.MenuTop
    $miAuto.Text = $T.MenuAuto; $miEdge.Text = $T.MenuEdge; $miFolder.Text = $T.MenuFolder; $miExit.Text = $T.MenuExit
    if ($MarkerHit) { $MarkerHit.ToolTip = $T.MarkerTip }
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

function Toggle-Window {
    if (Is-Docked) { if ($win.IsVisible) { Hide-Docked } else { Show-Docked; [void]$win.Activate() }; return }
    if ($win.IsVisible) { $win.Hide() } else { $win.Show(); [void]$win.Activate() }
}
function Set-Topmost([bool]$v) { if (-not (Is-Docked)) { $win.Topmost = $v }; $Cfg.Topmost = $v; $UI.BtnPin.Foreground = $(if ($v) { $Brush.Pin } else { $Brush.Dim }); Save-Settings }
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
$miTop.Add_Click({ Set-Topmost (-not [bool]$Cfg.Topmost) })
$miAuto.Add_Click({ try { Set-Autostart (-not (Test-Autostart)) } catch { Log "autostart: $_" } })
$miEdge.Add_Click({ try { Set-EdgeDock (-not [bool]$Cfg.EdgeDock) } catch { Log "edge dock: $_" } })
$miFolder.Add_Click({ Start-Process explorer.exe $AppDir })
$miExit.Add_Click({ Exit-App })

# ---------- window ----------
$UI.Root.Add_MouseLeftButtonDown({
    $x0 = $win.Left; $y0 = $win.Top
    try { $win.DragMove() } catch {}
    try { After-Drag $x0 $y0 } catch { Log "dock: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" }
})
$UI.C_Connect.Add_Click({ try { Start-ClaudeLogin } catch { Log "login: $_" } })
$UI.BtnPin.Add_Click({ Set-Topmost (-not [bool]$Cfg.Topmost) })
$UI.BtnKeep.Add_Click({ try { Toggle-KeepShown } catch { Log "keep shown: $_" } })
$UI.BtnHide.Add_Click({ $DockTimer.Stop(); $win.Hide(); $Marker.Hide() })

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

# ---------- edge docking: drag to a screen edge to tuck the widget away behind a small marker ----------
# Worked out in screen pixels (WinForms) and converted to WPF units for placing windows.
$CardMargin = 12          # transparent margin (shadow room) between the window edge and the visible card
# the marker is a small tab on the edge that shows how much is left for each service (its tighter limit), so you can
# read both without opening the widget; the dot is the service's color, the number is colored by how much is left
$MarkerSide = @{ W = 42; H = 42 }; $MarkerTop = @{ W = 84; H = 24 }

$MarkerXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Token Gauge marker" WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" ShowInTaskbar="False" Topmost="True" ShowActivated="False" Width="42" Height="42">
  <Border x:Name="Hit" Background="#01000000" Cursor="Hand">
    <Border x:Name="Bar" CornerRadius="0,8,8,0" Background="#F51B1D22" BorderBrush="#33FFFFFF" BorderThickness="1" Opacity="0.85">
      <StackPanel x:Name="Stack" HorizontalAlignment="Center" VerticalAlignment="Center">
        <StackPanel Orientation="Horizontal" Margin="2,1,2,1">
          <Ellipse Width="6" Height="6" Fill="#FFE0875F" VerticalAlignment="Center" Margin="0,0,4,0"/>
          <TextBlock x:Name="NumC" Text="—" Foreground="#80FFFFFF" FontSize="12" FontWeight="Bold" FontFamily="Segoe UI"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" Margin="2,1,2,1">
          <Ellipse Width="6" Height="6" Fill="#FF6E8BFF" VerticalAlignment="Center" Margin="0,0,4,0"/>
          <TextBlock x:Name="NumX" Text="—" Foreground="#80FFFFFF" FontSize="12" FontWeight="Bold" FontFamily="Segoe UI"/>
        </StackPanel>
      </StackPanel>
    </Border>
  </Border>
</Window>
'@
$Marker = [Windows.Markup.XamlReader]::Parse($MarkerXaml)
$MarkerHit = $Marker.FindName('Hit'); $MarkerBar = $Marker.FindName('Bar'); $MarkerStack = $Marker.FindName('Stack')
$MarkerNum = @{ C = $Marker.FindName('NumC'); X = $Marker.FindName('NumX') }
$MarkerHit.Add_MouseEnter({ $MarkerBar.Opacity = 1.0 })
$MarkerHit.Add_MouseLeave({ $MarkerBar.Opacity = 0.85 })
$MarkerHit.Add_MouseLeftButtonUp({ try { Show-Docked } catch { Log "dock show: $_" } })

function To-Px([double]$x, [double]$y) {
    $src = [System.Windows.PresentationSource]::FromVisual($win)
    if (-not $src) { return New-Object System.Windows.Point($x, $y) }
    return $src.CompositionTarget.TransformToDevice.Transform((New-Object System.Windows.Point($x, $y)))
}
function To-Dip([double]$x, [double]$y) {
    $src = [System.Windows.PresentationSource]::FromVisual($win)
    if (-not $src) { return New-Object System.Windows.Point($x, $y) }
    return $src.CompositionTarget.TransformFromDevice.Transform((New-Object System.Windows.Point($x, $y)))
}
function Get-CardRectPx {
    $a = To-Px ($win.Left + $CardMargin) ($win.Top + $CardMargin)
    $b = To-Px ($win.Left + $win.ActualWidth - $CardMargin) ($win.Top + $win.ActualHeight - $CardMargin)
    return @{ L = $a.X; T = $a.Y; R = $b.X; B = $b.Y }
}
# true when no monitor continues past this point (so this is an outer edge of the desktop, not a seam between screens)
function Test-OuterPoint([int]$x, [int]$y) {
    foreach ($sc in [System.Windows.Forms.Screen]::AllScreens) { if ($sc.Bounds.Contains($x, $y)) { return $false } }
    return $true
}
function Get-DockScreen {
    $d = $Cfg.Dock
    if (-not $d) { return $null }
    foreach ($sc in [System.Windows.Forms.Screen]::AllScreens) { if ($sc.DeviceName -eq $d.Screen) { return $sc } }
    return $null
}
function Is-Docked { return [bool]($Cfg.EdgeDock -and $Cfg.Dock -and (Get-DockScreen)) }

# after a real drag: which outer edge (left / right / top) was the widget dropped on, if any
function Find-DockEdge {
    $c = [System.Windows.Forms.Cursor]::Position
    $sc = [System.Windows.Forms.Screen]::FromPoint($c)
    $wa = $sc.WorkingArea; $bd = $sc.Bounds
    $r = Get-CardRectPx
    $th = 6
    $best = $null; $bestDist = [double]::MaxValue
    $cy = [Math]::Min([Math]::Max($c.Y, $wa.Top), $wa.Bottom - 1)
    $cx = [Math]::Min([Math]::Max($c.X, $wa.Left), $wa.Right - 1)
    if (($c.X -le $wa.Left + $th -or $r.L -le $wa.Left + 1) -and (Test-OuterPoint ($bd.Left - 1) $cy)) {
        $dist = [Math]::Min($c.X - $wa.Left, $r.L - $wa.Left); if ($dist -lt $bestDist) { $bestDist = $dist; $best = @{ Edge = 'left'; Pos = $cy } } }
    if (($c.X -ge $wa.Right - 1 - $th -or $r.R -ge $wa.Right - 1) -and (Test-OuterPoint $bd.Right $cy)) {
        $dist = [Math]::Min($wa.Right - 1 - $c.X, $wa.Right - $r.R); if ($dist -lt $bestDist) { $bestDist = $dist; $best = @{ Edge = 'right'; Pos = $cy } } }
    if (($c.Y -le $wa.Top + $th -or $r.T -le $wa.Top + 1) -and (Test-OuterPoint $cx ($bd.Top - 1))) {
        $dist = [Math]::Min($c.Y - $wa.Top, $r.T - $wa.Top); if ($dist -lt $bestDist) { $bestDist = $dist; $best = @{ Edge = 'top'; Pos = $cx } } }
    if ($best) { $best.Screen = $sc.DeviceName }
    return $best
}

function Get-DockGeometry {
    $sc = Get-DockScreen; $wa = $sc.WorkingArea
    $tl = To-Dip $wa.Left $wa.Top; $br = To-Dip $wa.Right $wa.Bottom
    $d = $Cfg.Dock
    $p = if ($d.Edge -eq 'top') { To-Dip ([double]$d.Pos) $wa.Top } else { To-Dip $wa.Left ([double]$d.Pos) }
    return @{ L = $tl.X; T = $tl.Y; R = $br.X; B = $br.Y; X = $p.X; Y = $p.Y }
}
function Clamp([double]$v, [double]$lo, [double]$hi) { if ($hi -lt $lo) { return $lo }; return [Math]::Min([Math]::Max($v, $lo), $hi) }

function Place-Marker {
    $g = Get-DockGeometry; $e = $Cfg.Dock.Edge
    if ($e -eq 'top') {
        $Marker.Width = $MarkerTop.W; $Marker.Height = $MarkerTop.H
        $Marker.Left = Clamp ($g.X - $MarkerTop.W / 2) $g.L ($g.R - $MarkerTop.W); $Marker.Top = $g.T
        $MarkerBar.CornerRadius = New-Object System.Windows.CornerRadius(0, 0, 8, 8); $MarkerStack.Orientation = 'Horizontal'
    } else {
        $Marker.Width = $MarkerSide.W; $Marker.Height = $MarkerSide.H; $MarkerStack.Orientation = 'Vertical'
        $Marker.Top = Clamp ($g.Y - $MarkerSide.H / 2) $g.T ($g.B - $MarkerSide.H)
        if ($e -eq 'left') {
            $Marker.Left = $g.L; $MarkerBar.CornerRadius = New-Object System.Windows.CornerRadius(0, 8, 8, 0)
        } else {
            $Marker.Left = $g.R - $MarkerSide.W; $MarkerBar.CornerRadius = New-Object System.Windows.CornerRadius(8, 0, 0, 8)
        }
    }
}
# put the card flush against the docked edge, next to where the marker is
function Place-DockedWindow {
    $g = Get-DockGeometry; $e = $Cfg.Dock.Edge
    $w = $win.ActualWidth; $h = $win.ActualHeight
    if ($e -eq 'top') {
        $win.Top = $g.T - $CardMargin
        $win.Left = Clamp ($g.X - $w / 2) ($g.L - $CardMargin) ($g.R - $w + $CardMargin)
    } else {
        $win.Top = Clamp ($g.Y - 40 - $CardMargin) ($g.T - $CardMargin) ($g.B - $h + $CardMargin)
        $win.Left = $(if ($e -eq 'left') { $g.L - $CardMargin } else { $g.R - $w + $CardMargin })
    }
}

$DockTimer = New-Object System.Windows.Threading.DispatcherTimer
$DockTimer.Interval = [TimeSpan]::FromMilliseconds(150)
$S.DockLastInside = Get-Date

function Hide-Docked {
    $DockTimer.Stop()
    $win.Hide()
    Place-Marker
    $Marker.Show()
}
function Show-Docked {
    if (-not (Is-Docked)) { $win.Show(); return }
    $Marker.Hide()
    $win.Topmost = $true
    $win.Show()
    Place-DockedWindow
    $S.DockLastInside = Get-Date
    if (-not $Cfg.Dock.Pinned) { $DockTimer.Start() }
}
# auto-hide once the mouse has left the card for a moment (not while a button is held, e.g. during a drag)
function Watch-Dock {
    if (-not (Is-Docked) -or $Cfg.Dock.Pinned -or -not $win.IsVisible) { $DockTimer.Stop(); return }
    if ([System.Windows.Forms.Control]::MouseButtons -ne [System.Windows.Forms.MouseButtons]::None) { $S.DockLastInside = Get-Date; return }
    $c = [System.Windows.Forms.Cursor]::Position; $r = Get-CardRectPx; $pad = 6
    if ($c.X -ge $r.L - $pad -and $c.X -le $r.R + $pad -and $c.Y -ge $r.T - $pad -and $c.Y -le $r.B + $pad) { $S.DockLastInside = Get-Date; return }
    if (((Get-Date) - $S.DockLastInside).TotalMilliseconds -gt 600) { Hide-Docked }
}
$DockTimer.Add_Tick({ try { Watch-Dock } catch { Log "dock watch: $_" } })

function Update-DockUI {
    $docked = Is-Docked
    $UI.BtnKeep.Visibility = $(if ($docked) { 'Visible' } else { 'Collapsed' })
    $UI.BtnKeep.Foreground = $(if ($docked -and $Cfg.Dock.Pinned) { $Brush.Pin } else { $Brush.Dim })
}
function Undock {
    $Cfg.Dock = $null; Save-Settings
    $DockTimer.Stop(); $Marker.Hide()
    $win.Topmost = [bool]$Cfg.Topmost
    if (-not $win.IsVisible) { $win.Show() }
    Update-DockUI
}
function Toggle-KeepShown {
    if (-not (Is-Docked)) { return }
    $Cfg.Dock.Pinned = -not [bool]$Cfg.Dock.Pinned; Save-Settings
    Update-DockUI
    if ($Cfg.Dock.Pinned) { $DockTimer.Stop() } else { $S.DockLastInside = Get-Date; $DockTimer.Start() }
}
function Set-EdgeDock([bool]$on) {
    $Cfg.EdgeDock = $on; Save-Settings
    if (-not $on -and $Cfg.Dock) { Undock }
}

# called after the user releases the mouse on the card
function After-Drag([double]$x0, [double]$y0) {
    if ([Math]::Abs($win.Left - $x0) -lt 2 -and [Math]::Abs($win.Top - $y0) -lt 2) { return }   # just a click, not a drag
    $hit = $null
    if ($Cfg.EdgeDock) { $hit = Find-DockEdge }
    if ($hit) {
        $keep = [bool]($Cfg.Dock -and $Cfg.Dock.Pinned)
        $Cfg.Dock = @{ Edge = $hit.Edge; Pos = [int]$hit.Pos; Screen = $hit.Screen; Pinned = $keep }
        Save-Settings
        Update-DockUI
        if ($keep) { Show-Docked } else { Hide-Docked }
    } else {
        if ($Cfg.Dock) { Undock }
        Save-Position
    }
}
$MarkerHit.ToolTip = $T.MarkerTip

# ---------- main loop ----------
function Tick {
    if ((Get-Date).Date -ne $S.Day) { Reset-Day; $S.NextLocal = [DateTime]::MinValue }
    $now = [DateTime]::UtcNow
    if ($now -ge $S.NextLocal) { Update-Local; $S.NextLocal = $now.AddSeconds($LocalRefreshSec) }
    # a new or renewed Claude login (e.g. right after signing in from the widget): fetch the limits at once
    $stamp = 0; try { if (Test-Path -LiteralPath $ClaudeCred) { $stamp = [IO.File]::GetLastWriteTimeUtc($ClaudeCred).Ticks } } catch {}
    if ($null -ne $S.CredStamp -and $stamp -ne $S.CredStamp -and $stamp -ne 0) { $S.NextQuota = [DateTime]::MinValue }
    $S.CredStamp = $stamp
    if ($now -ge $S.NextQuota) { Start-ClaudeQuotaFetch; $S.NextQuota = $now.AddSeconds($QuotaRefreshSec) }
    Poll-ClaudeQuota
    Render
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({ try { Tick } catch { Log "tick: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" } })

Load-QuotaCache
$startDocked = Is-Docked
if (-not $startDocked -and $Cfg.Dock) { $Cfg.Dock = $null }          # the screen it was docked to is gone
if ($startDocked -and -not $Cfg.Dock.Pinned) { $win.Opacity = 0 }   # avoid a flash before tucking it away
$win.Show()
if ($startDocked) {
    if ($Cfg.Dock.Pinned) { Show-Docked } else { Hide-Docked; $win.Opacity = 1 }
}
Update-DockUI
try { Tick } catch { Log "first tick: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" }
$timer.Start()
[void]$app.Run()
