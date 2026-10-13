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

**System Clean tab**
- Temp files, Windows Update cache, prefetch, Delivery Optimization cache, error reports
- Recycle Bin, DNS cache
- Full cleanup in one click
- Disable hibernation (frees hiberfil.sys)

**Safety**
- "Create Restore Point" button at the top, offered again before the one-click preset
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
- Bloatware removal is opt-in per category. Read the checkboxes before you apply.

## License

MIT. Use at your own risk.
