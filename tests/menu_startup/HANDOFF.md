# Main menu route smoke

Entry: `tests/menu_startup/test_menu_routes.gd` (`SceneTree` test).

Run after importing assets. Start the local relay in a separate terminal with
`npx wrangler dev --config relay/wrangler.jsonc --ip 127.0.0.1 --port 8787`.
Run the smoke test with isolated Godot user data:

```powershell
$env:LABVOLT_RELAY_URL = "ws://127.0.0.1:8787"
$env:APPDATA = Join-Path $PWD ('.godot/menu-smoke-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $env:APPDATA | Out-Null
& .\runtime\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe --headless --path . --script res://tests/menu_startup/test_menu_routes.gd
```

The test loads the real Main scene, checks button usability, and triggers the Play button on both Singleplayer and Host Game. It checks that gameplay opens, player control is enabled, and the session is offline or hosted as expected. Without the relay override, the test checks that Host Game requires a connected relay account. It also checks View Courses, Character Customizer, Settings, and their Back buttons. Expected output is `MENU_ROUTES PASS` with exit code 0. Investigate any script errors printed during the run.

This headless test emits button signals directly. Physical pointer input and visual quality require an interactive check.

## Reproducible relay and native checks

`run_menu_routes.py` starts the repository's actual Worker and DurableObject
with an already installed Wrangler, waits for `/health`, and runs Godot in
the same process environment and loopback namespace. It stores the log and
machine-readable result and rejects unexpected engine or script errors.
On Linux the three exact errors for the repository's Windows-only CEF extension
are reported separately; they are not silently discarded.

```sh
python3 tests/menu_startup/run_menu_routes.py \
  --godot /path/to/Godot_mono \
  --dotnet-root /path/to/dotnet \
  --wrangler /path/to/node_modules/wrangler/bin/wrangler.js \
  --output /tmp/labvolt-menu-headless
```

The companion `render_gameplay_startup.gd` sends physical pointer and Escape
input through the real viewport, enters Singleplayer, leaves through the menu,
then enters Host Game using the real relay. It checks actual player control,
faculty mounting, online mode and receipt of the room code. It captures the
menu and both gameplay routes and saves `native-gameplay.json`.

```sh
python3 tests/menu_startup/run_menu_routes.py \
  --godot /path/to/Godot_mono \
  --dotnet-root /path/to/dotnet \
  --wrangler /path/to/node_modules/wrangler/bin/wrangler.js \
  --output /tmp/labvolt-menu-native \
  --native --script tests/menu_startup/render_gameplay_startup.gd \
  --expected-pass 'MENU_STARTUP_RENDER PASS'
```

Use a new output directory for each run to keep saves isolated. `--native`
uses the existing display and OpenGL compatibility rendering. A Linux software
display can be launched in the same process environment using
`--xorg-display <display-number>` when Xorg and an appropriate dummy display
configuration are installed. Use separate `--port` and `--inspector-port`
values when loopback ports are constrained. This infrastructure is external to
the game and does not change production launch behavior.

Native startup rendering establishes menu and scene integration. It does not
verify live AI behavior, real synthesized voices, GPU frame rate, or complete
classroom interactions. Inspect the captured images as well as the result JSON.
