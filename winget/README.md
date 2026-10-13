# Shipping BALDYBEAST OPTIMIZER on winget

winget cannot install a bare .ps1, so the release ships a tiny compiled launcher
(exe) next to the script. The launcher source is inline in `build-release.ps1`,
it just starts `powershell -File Optimize.ps1` from its own folder. Nothing else.

## One time release steps

1. Build the asset:

   ```powershell
   powershell -ExecutionPolicy Bypass -File winget\build-release.ps1
   ```

   It compiles the launcher, zips `BaldyBeast.Optimizer.exe` + `Optimize.ps1` +
   `LICENSE` into `dist\BaldyBeast.Optimizer-win.zip`, and prints the SHA256.

2. On GitHub: create a release tagged `v1.2.0` (tag must match PackageVersion)
   and upload `dist\BaldyBeast.Optimizer-win.zip` with the exact asset name
   `BaldyBeast.Optimizer-win.zip`.

3. Paste the printed SHA256 into
   `winget\manifests\BaldyBeast.Optimizer.installer.yaml`
   (replace the zero placeholder).

4. Validate locally (needs winget 1.4+):

   ```powershell
   winget validate --manifest winget\manifests
   ```

## Submit to microsoft/winget-pkgs

1. Fork https://github.com/microsoft/winget-pkgs
2. Copy `winget\manifests\*.yaml` into
   `manifests\b\BaldyBeast\Optimizer\1.2.0\` in your fork
   (folder name is the version, files keep their names).
3. Open a pull request. Review usually takes a few days.
4. Once it merges, anyone can install with:

   ```powershell
   winget install BaldyBeast.Optimizer
   ```

## Every new version after that

- Bump `AppVersion` in `Optimize.ps1` (the tool's self-update reads it).
- Bump `PackageVersion` in all three manifests.
- Rerun `build-release.ps1`, make a new release tag, paste the new SHA256,
  submit the updated manifests the same way.
