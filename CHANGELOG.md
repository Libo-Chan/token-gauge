# Changelog

## 0.1.1 - 2026-11-08

- Fixed: Codex usage could stop updating when a Codex session ran past midnight. Windows does not refresh the last-write time of a log file that Codex keeps open, so that session was skipped; the widget now reads every session from the last few days and counts entries by their own timestamps.
- Claude plan limits now survive a restart or an expired login token: the last values are kept and shown with the time they are from.

## 0.1.0 - 2026-11-07

First public version.

- Claude Code and Codex: today's tokens with input / output / cache breakdown
- Plan limits left (5-hour and weekly) as colored bars with live reset countdown
- Low-quota notifications at 20 % and 10 % remaining (configurable)
- Tray icon colored by the tightest limit; always-on-top, start with Windows, refresh, exit
- Finds local Claude Code sessions created by the Claude desktop app as well as the CLI
- UI in English, Simplified Chinese, Traditional Chinese, Japanese and Korean, switchable live from the tray menu (follows the Windows language by default)
- Per-user installer and uninstaller, no admin rights needed
