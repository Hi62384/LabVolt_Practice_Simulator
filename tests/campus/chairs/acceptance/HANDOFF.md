# Rolling chair headless acceptance

Run in a separate, idle Godot process after the current play session ends:

```powershell
godot --headless --path "C:\Users\User1\Documents\GodotProjects\LabVolt_Practice_Simulator" --script res://tests/campus/chairs/acceptance/chair_acceptance.gd
```

Expected final line: `CHAIR_ACCEPTANCE_OK checks=...` with exit code 0. Any `CHAIR_ACCEPTANCE_FAIL` line or nonzero exit code is a failure. The script waits two physics frames after changing collision bodies and should finish within 60 seconds. It never opens the main scene or writes game saves. Running Godot may still import project resources in its own process; schedule it only when the user is done playing.

The fixture instantiates `test_player.gd`, which extends the production `first_person.gd` and overrides only its `down("crouch")` input seam. The initial headless run reached 32 checks and failed only the three Ctrl checks because synthetic key events did not update the state read by `Input.is_physical_key_pressed()`. The revised fixture supplies Ctrl through that seam while keeping the production `look` method under test. It also instantiates the production `rolling_chair.gd`. It uses minimal collision shapes and the chair's real `swivel` property; it does not call `build(game)`, which requires the full game's sound and mesh factories. The player is tested through `sit`, `look`, `_physics_process`, and `stand_up`; the chair through `_physics_process`. It covers relative yaw limits at three headings, pitch, Ctrl mode, resuming head look, spin input, heading on stand, a table-side exit, entry point blocked after seating, lack of a floor, and retry after floor restoration. A failed Ctrl check prints `CTRL_DIAG` with prior/current turn and head values.

Limits: The fixture does not verify captured-mouse or menu routing in `game.gd`, network packet delivery, host rejection of spoofed chair input, remote avatar animation, or multiplayer disconnect/rejoin. Those need an isolated game/network run and a live user playtest. It also does not model the full chair visual target collider, walls/corners, or multi-level room layouts. Source review confirms that `game.gd` sends `player.rotation.y` as pose yaw and authenticates chair input against the current occupant, but this fixture does not prove those paths at runtime.

Production seam note: `first_person.stand_up()` uses `get_world_3d().direct_space_state` internally and has no candidate-result API. This fixture therefore checks the resulting player position and occupancy state through the real method. No production seam is needed for these checks.
