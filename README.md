# Token Gauge

[简体中文](README.zh-CN.md) | English

A small always-on-top Windows desktop widget that tells you at a glance how long your **Claude Code** and **Codex** plans will last: how much is left, when it resets, and whether you will run out first at your current pace. No more opening the Usage page every few minutes.

> **Unofficial project.** Not affiliated with, endorsed by, or supported by Anthropic or OpenAI. "Claude" and "Codex" are trademarks of their respective owners and are used here only to describe what the tool reads.

<p align="center"><img src="docs/screenshot-en.png" alt="Token Gauge widget" width="300"></p>

## Features

- **What's left comes first**: one big number per service shows how much of its tightest limit (5-hour or weekly) is left; the other limit sits below it as a small line and a thin bar. Green above 50 % left, amber 20–50 %, red below 20 %
- **Pace forecast**: from your average rate so far in the window, it tells you whether you will make it to the reset, or roughly when you will run out and how long before the reset that is
- Time until reset ("resets in 4h 24m"); hover for the exact time
- Today's tokens as one quiet line (hover for the input / output / cache breakdown); hidden when there is nothing local to count
- **Low-quota notifications** when a limit drops below 20 % and 10 %
- **Sign in to Claude from the widget**: when you are not signed in yet or the login has ended, click "Connect Claude account" instead of typing commands from the docs
- Tray icon whose color follows your tightest limit; right-click menu for always-on-top, start with Windows, edge auto-hide, language, refresh, exit
- **5 UI languages**, switchable live from the tray menu: English, 简体中文, 繁體中文, 日本語, 한국어 (follows your Windows language by default)
- **Edge auto-hide**: drag it to the left, right or top edge of the screen and it tucks away behind a small tab that shows the % left for Claude Code and Codex; click the tab to bring it back
- Draggable, remembers its position
- Single PowerShell script on the built-in **Windows PowerShell 5.1 + WPF**. Nothing to install, no admin rights, no telemetry

## Requirements

- Windows 10 or 11
- **Codex**: the Codex CLI / app signed in with a ChatGPT plan. Data is read from `%USERPROFILE%\.codex\sessions`
- **Claude Code**: the Claude Code CLI signed in with a Claude subscription (Pro / Max), see below

## Install

1. Download the latest `token-gauge-x.y.z.zip` from [Releases](../../releases) and **extract the whole zip**.
2. Double-click **`install.cmd`**.
3. Answer whether it should start with Windows. The widget appears at the top-right of your screen.

It installs per-user to `%LOCALAPPDATA%\Programs\TokenGauge` and adds a **Token Gauge** entry to the Start menu.
To remove it, use **Uninstall Token Gauge** in the Start menu, or run `uninstall.cmd`.

> Windows SmartScreen or your antivirus may warn about scripts downloaded from the internet. All of the code is plain-text PowerShell in this repository, so you can read it before running.

### Getting the Claude quota to show

The Claude plan limits come from the same usage endpoint Claude Code itself uses, so Token Gauge needs the login token that the **Claude Code CLI** stores in `%USERPROFILE%\.claude\.credentials.json`. If you only use Claude through the desktop app, you need to sign in to the CLI once.

**The easy way: click "Connect Claude account" in the widget.** It opens a terminal that runs `claude auth login`; sign in with your subscription in the browser. If the Claude Code CLI is not installed yet, it is installed first with the official script. The widget picks up the new login by itself.

Or do it by hand:

```powershell
irm https://claude.ai/install.ps1 | iex   # install Claude Code CLI (official installer)
claude auth login                          # sign in with your subscription
```

This token only lasts a few hours. Token Gauge keeps it fresh by itself: shortly before it expires, it runs `claude auth status` in the background (no window, no quota used, at most once every 10 minutes), which makes the official CLI renew the token. Token Gauge only **reads** the token and never modifies it.

## Where the numbers come from

| Shown | Claude Code | Codex |
|---|---|---|
| Today's tokens | Local session logs `~\.claude\projects\**\*.jsonl` (also the desktop app's local sessions) | Local session logs `~\.codex\sessions\**\rollout-*.jsonl` |
| 5-hour / weekly limits | `GET https://api.anthropic.com/api/oauth/usage` with your Claude Code token | `rate_limits` recorded in the latest Codex session log |

Notes:

- **Cloud sessions are not counted in "today's tokens".** Sessions that run in the cloud (for example Claude Code on the web or cloud sessions in the desktop app) leave no logs on your PC. Their usage still counts toward the plan limits, which are shown correctly.
- **Codex limits update when you use Codex.** The values are as of your last Codex request. Once the reset time passes, the bar shows the window as reset.
- Token totals include cache reads/writes, matching what the logs record. Subscription plans don't publish token-based limits, so the percentage bars are the numbers that actually matter.
- The Claude usage endpoint is **undocumented** and may change or stop working without notice.

## Privacy

- Reads only local files under your user profile plus the one Anthropic usage endpoint above.
- When the Claude Code login token is about to expire, it runs the official `claude auth status` command in the background so the CLI renews it.
- Sends nothing anywhere else. No analytics, no update checks.
- Settings and an error log live in `%APPDATA%\TokenGauge`.
- "Connect Claude account" opens a terminal that runs the official `claude auth login` (and, if the CLI is missing, the official installer `https://claude.ai/install.ps1` first).

## Edge auto-hide

- **Hide**: drag the widget to the left, right or top edge of the screen and release. It hides and leaves a small tab at the edge where you dropped it.
- **Show**: click the tab. The widget slides back next to it and hides again about half a second after the mouse leaves it.
- The tab shows the % left for both Claude Code (orange dot) and Codex (blue dot), each for its tighter limit and colored green, amber or red, so you can read them without opening the widget.
- **Keep it visible**: drag it anywhere away from the edges, or, while it is at an edge, click the eye button in its title bar ("keep shown"). Click the eye again to go back to auto-hide.
- Only outer edges of your desktop count. The edge between two monitors does not, so moving the widget to another screen never hides it. The bottom edge (usually the taskbar) is not used.
- To turn the feature off: right-click the tray icon → **Auto-hide at screen edge**.

## Settings

Every setting is in the tray icon's right-click menu and takes effect immediately; there is no file to edit:

- **Language**: 5 languages, or follow Windows
- **Always on top**, **Start with Windows**, **Auto-hide at screen edge**

The notification levels (20 % and 10 % left) and refresh intervals (local logs every 15 s, Claude limits every 2 min) are fixed.

Environment variables `CLAUDE_CONFIG_DIR` and `CODEX_HOME` are respected.

## Troubleshooting

- **Nothing appears:** check the tray (click `^` to see hidden icons). Run `powershell -ExecutionPolicy Bypass -STA -File "%LOCALAPPDATA%\Programs\TokenGauge\TokenGauge.ps1"` from a terminal to see errors, and look in `%APPDATA%\TokenGauge\error.log`.
- **Claude asks you to sign in:** click "Connect Claude account" in the widget, see above.
- **Claude: "Login expired" and the limits are old:** the widget renews the token automatically (see above), so this should clear up within a few minutes. If it stays, click "Sign in to Claude again". Until then the widget keeps showing the last limits it fetched, with the time they are from.
- **No pace forecast:** right after a window starts there is too little data to say anything useful, so it is hidden: for the first 15 minutes of a 5-hour window and the first ~8 hours of a weekly window.
- **How the pace forecast works:** it uses your average rate since the window started. For the weekly limit that average already includes the hours you sleep or take off, so one busy hour does not set off a warning.
- **Codex: today's tokens or limits stop updating:** fixed in 0.1.1. Older versions skipped a Codex session that ran past midnight, because Windows does not refresh the last-write time of a log file that Codex keeps open. Update to the latest release.
- **"Today" went back to a small number after midnight:** expected. "Tokens today" counts from your local midnight. The plan limits are separate and keep their own 5-hour and weekly windows.
- **Claude: "network error":** the widget uses your system proxy settings. Make sure `api.anthropic.com` is reachable.
- **Codex shows no limits:** use Codex once. Limits are only recorded when a request is made.

## Contributing

Issues and pull requests are welcome. Translations other than English and Simplified Chinese were written without a native-speaker review, so corrections are especially welcome; all UI text lives in the `$Strings` table near the top of `src/TokenGauge.ps1`, and adding a language means copying the `en` block and adding its code to `$LangOrder`. Log formats of Claude Code and Codex change from time to time; if numbers look wrong after an update, please open an issue with your tool versions and a screenshot (redact anything private).

## License

[MIT](LICENSE)
