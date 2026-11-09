# Startup verification

After changing game code, scenes, or project configuration, run the menu startup smoke test with isolated Godot user data before handing off. It must pass both the Singleplayer and Host Game Play routes. Fix startup script errors even if the menu itself still appears. See [the test instructions](tests/menu_startup/HANDOFF.md).
