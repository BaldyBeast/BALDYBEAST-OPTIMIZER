<#
    Builds the winget release asset for BALDYBEAST OPTIMIZER.

    Run:  powershell -ExecutionPolicy Bypass -File winget\build-release.ps1

    Produces dist\BaldyBeast.Optimizer-win.zip containing:
      BaldyBeast.Optimizer.exe  (tiny launcher, source is inline below)
      Optimize.ps1              (the actual tool)
      LICENSE

    Then:
      1. Create a GitHub release tagged v<version> and upload the zip.
      2. Paste the printed SHA256 into manifests\BaldyBeast.Optimizer.installer.yaml.
      3. See winget\README.md for the submission steps.
#>

$ErrorActionPreference = 'Stop'

$wingetDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot  = Split-Path -Parent $wingetDir
$distDir   = Join-Path $repoRoot 'dist'
$zipPath   = Join-Path $distDir 'BaldyBeast.Optimizer-win.zip'

$scriptPath = Join-Path $repoRoot 'Optimize.ps1'
$licensePath = Join-Path $repoRoot 'LICENSE'
if (-not (Test-Path -LiteralPath $scriptPath)) { throw "Optimize.ps1 not found at $scriptPath" }
if (-not (Test-Path -LiteralPath $licensePath)) { throw "LICENSE not found at $licensePath" }

# Version comes straight from the tool so the two can never drift
$versionMatch = [regex]::Match([IO.File]::ReadAllText($scriptPath), "AppVersion\s*=\s*'([0-9\.]+)'")
if (-not $versionMatch.Success) { throw 'Could not read AppVersion from Optimize.ps1' }
$version = $versionMatch.Groups[1].Value
Write-Host ("Building BALDYBEAST OPTIMIZER v{0}" -f $version) -ForegroundColor Yellow

if (Test-Path -LiteralPath $distDir) {
    Remove-Item -LiteralPath $distDir -Recurse -Force
}
New-Item -Path $distDir -ItemType Directory -Force | Out-Null

# ---------------------------------------------------------------------------
# Launcher exe: starts the tool with Windows PowerShell, no install needed
# ---------------------------------------------------------------------------
$launcherSource = @'
using System;
using System.Diagnostics;
using System.IO;

namespace BaldyBeast
{
    public static class Launcher
    {
        public static void Main(string[] args)
        {
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string script = Path.Combine(baseDir, "Optimize.ps1");
            if (!File.Exists(script))
            {
                Console.Error.WriteLine("Optimize.ps1 is missing next to the launcher.");
                Environment.Exit(1);
            }
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = "powershell.exe";
            psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\"";
            psi.UseShellExecute = true;
            Process.Start(psi);
        }
    }
}
'@

$exePath = Join-Path $distDir 'BaldyBeast.Optimizer.exe'
Add-Type -TypeDefinition $launcherSource -OutputAssembly $exePath -OutputType ConsoleApplication
Write-Host 'Launcher compiled: BaldyBeast.Optimizer.exe' -ForegroundColor Green

Copy-Item -LiteralPath $scriptPath -Destination (Join-Path $distDir 'Optimize.ps1')
Copy-Item -LiteralPath $licensePath -Destination (Join-Path $distDir 'LICENSE')

Compress-Archive -Path (Join-Path $distDir 'BaldyBeast.Optimizer.exe'), (Join-Path $distDir 'Optimize.ps1'), (Join-Path $distDir 'LICENSE') -DestinationPath $zipPath -Force

$sha256 = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
$zipSizeMb = [math]::Round((Get-Item -LiteralPath $zipPath).Length / 1MB, 2)

Write-Host ''
Write-Host 'Release asset ready' -ForegroundColor Green
Write-Host ('  file    : {0}' -f $zipPath)
Write-Host ('  size    : {0} MB' -f $zipSizeMb)
Write-Host ('  version : {0}' -f $version)
Write-Host ('  SHA256  : {0}' -f $sha256) -ForegroundColor Cyan
Write-Host ''
Write-Host 'Next steps:' -ForegroundColor Yellow
Write-Host ('  1. Create a GitHub release tagged v{0} and upload the zip as BaldyBeast.Optimizer-win.zip' -f $version)
Write-Host ('  2. In manifests\BaldyBeast.Optimizer.installer.yaml set PackageVersion: {0} and InstallerSha256: {1}' -f $version, $sha256)
Write-Host '  3. Follow winget\README.md to submit the manifests to microsoft/winget-pkgs'
