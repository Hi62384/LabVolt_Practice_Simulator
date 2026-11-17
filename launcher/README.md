# Windows launcher

Players download `LabVoltLauncher.exe` from the latest GitHub release. On startup it checks the release manifest, verifies the downloaded blocks, and enables Play after installing the game. Checks bypass cached latest-release redirects; interrupted, stalled, or invalid transfers are retried. A working local version remains available when the update fails. Game files live under `%LOCALAPPDATA%\LabVolt Launcher`. The game's own saves live separately in its existing Godot user-data folder, preserving saves made under the old name.

The launcher updates the game, not its own executable. To receive launcher improvements, replace the launcher with the newly built or newly released executable; doing so preserves the installed game and saves.

Pushes to `windows-launcher` run **Publish Windows game**. The workflow checks both Play routes, exports the Windows game, verifies the update logic, and uploads an entire draft release before making it current. Future releases must keep the version 1 manifest format and the repository address compatible with existing launchers. A private repository requires an alternative public download feed for players who have no GitHub access.

Build the launcher with `./launcher/build.ps1`. Run `python launcher/test_updates.py` to verify fresh checks, stalled and corrupt transfer retries, clean installation, an unchanged release, incremental updates, and fallback after a failed update.
