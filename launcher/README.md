# Windows launcher

Players download `LabVoltLauncher.exe` from the latest GitHub release and keep that executable. On startup it checks the release manifest, verifies the downloaded blocks, and enables Play after installing the game. A working local version remains available when the update fails. Game files live under `%LOCALAPPDATA%\LabVolt Launcher`. The game's own saves live separately in its normal Godot user-data folder.

Pushes to `windows-launcher` run **Publish Windows game**. The workflow checks both Play routes, exports the Windows game, verifies the update logic, and uploads an entire draft release before making it current. Future releases must keep the version 1 manifest format and the repository address compatible with existing launchers. A private repository requires an alternative public download feed for players who have no GitHub access.

Build the launcher with `./launcher/build.ps1`. Run `python launcher/test_updates.py` to verify a clean install, an unchanged release, an incremental update, and a corrupt update.
