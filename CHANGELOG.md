# Changelog

## 0.2.1 - 2026-11-11

- Claude plan limits keep updating on their own. The Claude Code CLI's login token only lasts a few hours; when it is about to expire (or has expired), Token Gauge now runs `claude auth status` in the background, which makes the official CLI renew it, and fetches the limits again. No window opens, no quota is used, and it runs at most once every 10 minutes. Token Gauge still only reads the token.

## 0.2.0 - 2026-11-08

- New: edge auto-hide. Drag the widget to the left, right or top edge of the screen and let go: it tucks away and leaves a small translucent marker where you dropped it. Click the marker to bring the widget back; it hides again when the mouse leaves. Drag it away from the edge to keep it on screen as before.
- New: "keep shown" button (eye icon) appears while docked at an edge, so the widget stays visible there without auto-hiding.
- New: tray menu option to turn edge auto-hide off.
- The marker uses the same green / amber / red color as the tray icon.

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
