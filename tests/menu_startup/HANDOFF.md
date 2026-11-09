# Main menu route smoke

Entry: `tests/menu_startup/test_menu_routes.gd` (`SceneTree` test).

Run after importing assets. Use a separate PowerShell session with an isolated Godot user-data directory:

```powershell
$env:APPDATA = Join-Path $PWD ('.godot/menu-smoke-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $env:APPDATA | Out-Null
& .\runtime\Godot_v4.5.1-stable_win64_console.exe --headless --path . --script res://tests/menu_startup/test_menu_routes.gd
```

The test loads the real Main scene, checks button usability, and triggers the Play button on both Singleplayer and Host Game. It checks that gameplay opens, player control is enabled, and the session is offline or hosted as expected. Host Game needs its default UDP port available. It also checks View Courses, Character Customizer, Settings, and their Back buttons. Expected output is `MENU_ROUTES PASS` with exit code 0. Investigate any script errors printed during the run.

This headless test emits button signals directly. Physical pointer input and visual quality require an interactive check.
