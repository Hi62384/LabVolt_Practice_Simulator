# Actual menu and gameplay startup verification

## Result

Both the baseline at `7ec6c95241fca70e724783d6234dc3f445a6630c` and the
`dev/character-dossiers-20261127` integration tree passed the mandatory
Singleplayer and Host Game Play routes. Each run used the real `Main.tscn`,
the production menu, session, player and faculty modules, and the repository's
actual Worker relay with its DurableObject implementation.

The native companion also delivered real pointer and Escape input through the
viewport and captured the rendered menu and gameplay. All three final current
images were inspected individually. The assertions confirmed that player control and
faculty were mounted, Singleplayer remained offline, Host Game was online,
and a real relay room code was received. These checks did not substitute a
fake session or emit the Play button signal in the native companion.

| Run | Result | Godot process duration | Complete harness duration |
| --- | --- | ---: | ---: |
| Baseline headless menu suite | PASS | 15.87 s | 20.93 s |
| Final current headless menu suite | PASS | 14.73 s | 20.06 s |
| Baseline native pointer and rendering | PASS | 50.40 s | 56.67 s |
| Final current native pointer and rendering | PASS | 27.10 s | 32.62 s |

These are observed runtimes of test processes, including scene construction,
explicit frame waits, captures and teardown. They are not AI response latency,
character-generation latency, a controlled frame-rate benchmark, or evidence
that gameplay became a particular percentage faster. Software rendering,
warm filesystem caches and concurrent integration work affect these durations.

## Runtime and isolation

- Godot `4.5.1.stable.mono.official.f62fdbde1`, the project-compatible Mono build.
- .NET SDK 8.0.428; the actual C# project was built before startup testing.
- Native display: X11, OpenGL compatibility, Mesa llvmpipe software renderer.
- Actual repository relay through Wrangler 4.158.0, matching the production
  release workflow's pinned version. The relay and game ran under one parent
  process in the same loopback namespace.
- Separate disposable user-data directories for every baseline and current
  run; no existing user identity or save was overwritten.
- No configured live AI credentials were available. No online character or
  speech provider was simulated as evidence of live quality.

All four startup runs exited successfully and produced no unexpected engine
or GDScript errors. Each printed the same three known Linux errors for the
repository's Windows-only CEF extension. The runner enumerates those exact
messages separately in `result.json`; any additional error fails the gate.
Compatibility-renderer warnings and software-rendering frame rate are not
hidden. Windows CEF and GPU rendering remain unverified in this environment.

## Evidence

The `startup/` directory contains the unmodified startup logs, result JSON,
native state assertions and six gameplay/menu images for the two native runs.
`capture-manifest.json` records file sizes and SHA-256 hashes. The captured
current tree was the frozen working tree after checkpoint
`d55cd873841e4c5dc299d58075766f07e2bcba48`, as identified in that manifest;
it does not claim to be a later final commit. The referenced regression source
manifest records all 684 production script hashes, which were unchanged
between the start and completion of the final affected-suite retakes.

- `startup/baseline-headless/` and `startup/current-headless/`: mandatory menu
  routes, including the real hosted Play path.
- `startup/baseline-native/` and `startup/current-native/`: pointer-driven
  route logs, renderer metadata, menu and gameplay captures.
- `startup/baseline-regressions.json`: all 33 preexisting default character
  regression suites passed on the baseline, including the actual gameplay
  memory, discipline, classmate, faculty and speech integration suites.

The native main-scene captures verify startup and scene integration. They do
not replace the separate facial-expression render matrix, inspector layout
renders, detailed classroom regression suites, multiplayer authorization
tests, or live model acceptance. Numerical reaction and local provider
fixture tests do not establish natural character dialogue or real vocal
delivery.

## Reproduction

See `tests/menu_startup/HANDOFF.md` for the headless and native commands.
`run_menu_routes.py` starts and checks the real local relay, runs the chosen
SceneTree probe, captures results and terminates only its own child processes.
`render_gameplay_startup.gd` is the pointer-driven native probe. The software
display option exists solely in verification infrastructure; production
startup behavior was not changed to accommodate this environment.
