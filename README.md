# BALDYBEAST OPTIMIZER

```
######   #####  #       ######  #     # ######  #######  #####   #####  #######
#     # #     # #       #     # #     # #     # #       #     # #          #
######  #     # #       #     #  #   #  ######  #####   #     #  #####     #
#     # ####### #       #     #   # #   #     # #       #######       #    #
#     # #     # #       #     #    #    #     # #       #     # #     #    #
######  #     # ######  ######     #    ######  ####### #     #  #####     #
```

Windows 10 / 11 gaming optimization, debloat and cleanup utility.
Single file. Pure PowerShell + WPF. No external DLLs, no installers, no background services.

## Quick start

One line, run in PowerShell (it asks for admin rights itself):

```powershell
irm "https://raw.githubusercontent.com/BaldyBeast/BALDYBEAST-OPTIMIZER/main/Optimize.ps1" | iex
```

Or clone the repo and run the file directly:

```powershell
powershell -ExecutionPolicy Bypass -File Optimize.ps1
```

## What's new in v1.3

- **Benchmark tab**: CPU single and multi thread, memory copy and disk tests in
  about 10 seconds. Save a baseline, apply your tweaks, run again and compare
  with real percentages. No fake FPS claims, just measurements.
- **Memory panel (RAMMap style)**: standby cache, modified page list and cache
  breakdown plus top processes by working set, and a Purge Standby List button
  that releases cached file pages instantly (same mechanism RAMMap and ISLC
  use, built in, no external tools).
- **Recommended tab**: taskbar tweaks (left alignment, hide search box, hide
  Task View button) and a display refresh rate reminder with a one click jump
  into Windows Display settings.
- **Support bundle**: one button zips hardware info, tweak selection, benchmark
  results and the log onto your Desktop for GitHub issues.
- **Desktop shortcut**: stop typing the one-liner.
- **Classic right-click menu** toggle for Windows 11.

## What's new in v1.2

- **Startup manager**: see everything that launches with Windows and disable it
  with one click. Disabled entries are quarantined in a registry key, never
  deleted, and the Backups tab brings them back.
- **Network tab**: switch DNS between Cloudflare, Google, Quad9, AdGuard or
  automatic, test latency to each resolver and your gateway, and set the
  wireless adapter to Maximum Performance. DNS changes are rollback covered.
- **winget packaging**: `winget/build-release.ps1` builds the release zip with a
  tiny launcher exe, so the tool can go on the Windows package manager. See
  `winget/README.md`.

## What's new in v1.1

- **Rollback points**: every registry, service and scheduled task change is recorded
  automatically before it is applied. The Backups tab restores the exact previous
  state of any session with one click.
- **Risk badges and tooltips**: every option is color tagged Safe / Recommended /
  Advanced and hovering it explains in one plain sentence what it does.
- **Profiles**: save and load your checkbox selection as shareable JSON files, plus
  built-in presets (Competitive FPS, Streaming, Clean Install Debloat).
- **Hardware tab**: OS, CPU, GPU, driver, memory, disks, page file, uptime and active
  power plan at a glance.
- **Self update**: the About tab checks GitHub for a newer version and installs it.

## What you get

**Gaming Tweaks tab**
- Ultimate Performance power plan (falls back to High Performance)
- Mouse acceleration off (Enhance Pointer Precision disabled and applied instantly)
- Game DVR and background recording disabled (GameConfigStore + AppCaptureEnabled + policy)
- Fullscreen optimizations disabled
- Game Mode on, Game Bar popups off
- Hardware-Accelerated GPU Scheduling on (HwSchMode = 2)
- MMCSS network throttling removed, Games task GPU / IO priority raised
- USB selective suspend off
- Visual effects set for best performance

**Debloat and Services tab**
- Bloatware removal per category (Bing apps, 3D apps, Solitaire and Xbox companion, consumer apps, Cortana)
- Telemetry, DiagTrack and CEIP scheduled tasks disabled
- Unneeded services disabled (Maps Broker, Retail Demo, WMP Network Sharing)
- Cortana and web search in the taskbar disabled
- Background apps disabled globally
- Consumer experiences, suggested apps and Start menu ads disabled
- Activity history, Widgets, Copilot and Windows Recall disabled
- OneDrive autostart entry removed (files untouched)
- Classic Windows 11 right-click menu toggle

**System Clean tab**
- Temp files, Windows Update cache, prefetch, Delivery Optimization cache, error reports
- Recycle Bin, DNS cache
- Full cleanup in one click
- Disable hibernation (frees hiberfil.sys)

**Hardware tab**
- Full system readout: OS, CPU, GPU, driver, memory, disks, page file, uptime, power plan
- RAMMap style memory breakdown and top processes by working set
- Purge Standby List button

**Startup tab**
- Every Run registry entry listed (HKCU, HKLM and 32-bit) with its command
- Disable / enable with one click, quarantined not deleted

**Network tab**
- DNS switcher (Cloudflare, Google, Quad9, AdGuard, automatic)
- Latency test to each resolver and your default gateway
- Wireless adapter power saving to Maximum Performance

**Benchmark tab**
- CPU single and multi thread, memory copy, disk write and read
- Baseline save and compare with percentage deltas

**Recommended tab**
- Taskbar left alignment, hide search box, hide Task View button
- Display refresh rate reminder and shortcut into Display settings

**Safety**
- "Create Restore Point" button at the top, offered again before the one-click preset
- Automatic rollback points for every registry, service, task and DNS change
- Every change is logged live in the GUI console and to `%TEMP%\BaldyBeast-Optimizer.log`
- Confirmation dialogs before anything destructive
- Gaming Services and Xbox Game Bar are kept so Game Pass and captures keep working

**One click**
- "Optimize Everything (Gaming Ready)" selects the recommended set, applies everything and asks for a restart when needed

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 (built in) or PowerShell 7+
- Administrator rights (the tool elevates itself)

## Notes

- HAGS and power plan details need a restart to take effect.
- Windows only allows one restore point every 10 hours. A recent existing point still protects you.
- Bloatware removal is opt-in per category. Read the tooltips before you apply.
- Rollback covers registry, services, scheduled tasks and DNS. App removals and power
  plan switches are not covered there, use System Restore or reinstall the app for those.
- Benchmark scores only compare on the same machine and PowerShell version.

## License

MIT. Copyright (c) 2026 BaldyBeast. Use at your own risk.
