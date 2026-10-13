# BALDYBEAST OPTIMIZER

![CI](https://github.com/BaldyBeast/BALDYBEAST-OPTIMIZER/actions/workflows/ci.yml/badge.svg)

Every push runs the full validation harness, PSScriptAnalyzer and a UI render pass.
Check the Actions tab for the latest run, including screenshots of every tab.

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

## What's new in v1.9

- **Event log forensics**: scans 48 hours of System and Application logs for
  the classic failure signatures (display driver TDR resets, disk and file
  system errors, unexpected shutdowns and bugchecks, app crashes, out of
  memory events) and writes a verdict.
- **Driver age report**: GPU, audio and network driver versions and dates with
  VERY OLD flags past a year.
- **Disk SMART and latency**: temperature, wear, power-on hours, read/write
  error totals plus live per-disk read and write latency in milliseconds.
- **Top resource users**: live top 5 by CPU and RAM, sampled over 2 seconds.
- **Timer resolution display** (current, finest, coarsest).
- **Latency chart**: the packet loss monitor now plots its last 90 samples as
  a live WPF chart with red marks on lost packets.
- **Thermal throttle test**: 20 seconds of full CPU load while watching
  processor performance, verdict on whether clocks collapsed.
- **DNS race**: measures real lookups against Cloudflare, Google, Quad9 and
  AdGuard and names the fastest from your line.
- **Custom ping targets**: add your game server IPs to the packet loss monitor.
- **Health score**: the system health check now ends with an itemized
  PASS/WARN/FAIL list and a transparent score out of 100.

## What's new in v1.8

- **Snappy GUI**: all monitoring (memory sampling, performance counters, pings,
  game detection, auto-purge) moved off the UI thread onto a background worker.
  Tab switching and clicks are instant now, even with every monitor running.
- **Tab pre-warming**: every tab is laid out once at startup so the first click
  on each is instant too.

## What's new in v1.7.1

- **CDN-immune updates**: the update check now resolves the exact commit on
  GitHub and downloads from that immutable URL, so a cached `main` can never
  hand you an older version again. If you ever want a specific build right now,
  run the one-liner with the commit SHA from the GitHub commit list.

## What's new in v1.7

- **Diagnostics tab**: live stutter watch (DPC latency, disk queue, memory
  pressure), packet loss and ping spike monitor, a 5 second bottleneck scanner
  with a plain-English verdict, and a system health check covering disk health,
  free space, dirty volume flag, ACPI thermals and the Windows image store.
- **Windows repair**: `sfc /scannow` and `DISM /Online /Cleanup-Image /RestoreHealth`
  buttons that run in their own windows, plus Full Repair (DISM then SFC, the
  correct order).
- **Fixed (again)**: dropdown text colors were still wrong in some states.
  Foreground is now explicit at every template level (closed box, rows, selected
  row).
- **Fixed (again)**: the console now always closes with the GUI. Set
  `BALDYBEAST_KEEP_SHELL=1` first if you want the shell to survive.

## What's new in v1.6

- **Fixed**: dropdown menus (Windows Update, power plan, DNS) rendered white on
  white and were unreadable. All dropdowns now use a proper dark template.
- **Fixed**: closing the GUI left its console window open. The console now
  closes with the window when the tool owns it (shortcut, relaunch, -File).
- **Tray mode**: minimize to the system tray with quick actions (reopen, purge
  standby list, exit) from the tray icon.
- **Game launch detection**: optionally purges the standby list automatically
  when a game from the Games tab list starts.
- **Profile sharing**: load a profile straight from any https URL in the
  Profiles tab, plus three official presets in the `presets/` folder
  (Competitive FPS, Streaming, Fresh PC).

## What's new in v1.5

- **Fresh Install Kit (Apps tab)**: tick a curated essentials list (browsers,
  Steam, Epic, Discord, 7-Zip, PowerToys, VLC, OBS, VC++ runtimes) and install
  everything in one winget batch. Nothing bundled, installs come from the
  publishers.
- **Per-game tuning (Games tab)**: auto-detects Steam games (or add any exe),
  then per game forces the high performance GPU and disables fullscreen
  optimizations. Current flags are shown when you select a game.
- **Windows Update control**: defer updates 7/14/30 days, block driver updates
  through Windows Update, never auto-restart while signed in.
- **Power plan editor**: CPU min/max state, PCIe power saving and display off
  timeout written to your active plan.
- **Standby monitor**: opt-in auto-purge of the standby list when free RAM drops
  under a threshold, active only while the tool is open.
- **Dry-run preview**: bloatware removal now shows the exact package list before
  deleting anything.

## What's new in v1.4

- **Continuous integration**: every push runs the full validation harness (10
  tests), PSScriptAnalyzer and the UI render pass on GitHub Actions, and uploads
  the tab screenshots as build artifacts. Nothing broken reaches users.
- **Automated releases**: pushing a `v*` tag builds the release zip with its
  SHA256 and publishes it as a GitHub Release, ready for winget submission.
- **Windows System Restore, in the Backups tab**: lists every restore point and
  can restore the whole PC to any of them with one click.
- **Build awareness**: options that do not apply to your Windows build (Windows
  11 only tweaks on Windows 10, Recall before 24H2) are greyed out automatically
  with a tooltip explaining why.
- **Recall snapshot wipe**: the Clean tab now deletes Windows Recall snapshot
  data that was already captured.
- **Polish**: tooltips on the header buttons, clearer safety wording everywhere.

## What's new in v1.3.1

- **Fixed**: Purge Standby List failed with status 0xC000000D on some systems.
  The memory list command value now covers both API enum conventions.
- **Fixed**: "Download and Restart" looked broken because it was greyed out when
  no update existed. It is always available now and doubles as a repair.
- **Better layout**: tabs fit on one row, taller window, action buttons moved to
  the top of the About tab, and a Purge Standby List button added to the Clean
  tab where the cleanup tools live. The window title now shows the version.

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

**Gaming tab**
- Ultimate Performance power plan (falls back to High Performance)
- Mouse acceleration off (Enhance Pointer Precision disabled and applied instantly)
- Game DVR and background recording disabled (GameConfigStore + AppCaptureEnabled + policy)
- Fullscreen optimizations disabled
- Game Mode on, Game Bar popups off
- Hardware-Accelerated GPU Scheduling on (HwSchMode = 2)
- MMCSS network throttling removed, Games task GPU / IO priority raised
- USB selective suspend off
- Visual effects set for best performance

**Debloat tab**
- Bloatware removal per category (Bing apps, 3D apps, Solitaire and Xbox companion, consumer apps, Cortana)
- Telemetry, DiagTrack and CEIP scheduled tasks disabled
- Unneeded services disabled (Maps Broker, Retail Demo, WMP Network Sharing)
- Cortana and web search in the taskbar disabled
- Background apps disabled globally
- Consumer experiences, suggested apps and Start menu ads disabled
- Activity history, Widgets, Copilot and Windows Recall disabled
- OneDrive autostart entry removed (files untouched)
- Classic Windows 11 right-click menu toggle

**Clean tab**
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
