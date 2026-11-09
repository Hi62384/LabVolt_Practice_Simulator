# Main menu route smoke

Entry: `tests/menu_startup/test_menu_routes.gd` (`SceneTree` test).

Run after importing assets. Start the local relay in a separate terminal with
`npx wrangler dev --config relay/wrangler.jsonc --ip 127.0.0.1 --port 8787`.
Run the smoke test with isolated Godot user data:

```powershell
$env:LABVOLT_RELAY_URL = "ws://127.0.0.1:8787"
$env:APPDATA = Join-Path $PWD ('.godot/menu-smoke-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $env:APPDATA | Out-Null
& .\runtime\Godot_v4.5.1-stable_win64_console.exe --headless --path . --script res://tests/menu_startup/test_menu_routes.gd
```

The test loads the real Main scene, checks button usability, and triggers the Play button on both Singleplayer and Host Game. It checks that gameplay opens, player control is enabled, and the session is offline or hosted as expected. Without the relay override, the test checks that Host Game requires a connected relay account. It also checks View Courses, Character Customizer, Settings, and their Back buttons. Expected output is `MENU_ROUTES PASS` with exit code 0. Investigate any script errors printed during the run.

This headless test emits button signals directly. Physical pointer input and visual quality require an interactive check.
