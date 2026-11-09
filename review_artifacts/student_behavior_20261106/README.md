# Campus student behavior handoff

Source-only implementation. Runtime/visual acceptance has not been claimed or performed while the user is playing.

## Lifecycle

`student_behavior.gd` owns a deterministic population capped at 24 and advances it at 8 Hz. Each student independently alternates between corridor wandering, a route through the registry-authored approach and door, an 18–55 second work dwell at an in-bounds room point, and a route back through the same real door. Room choice and dwell time are stable per student/cycle and are intentionally desynchronized.

`local_crowd.gd` keeps this simulation alive across room/hall context changes. Context changes no longer clear routes or recreate identities. Visual allocation remains staggered at one pooled mesh per 0.2 seconds. Hidden students remain lightweight dictionary state, not active physics/navigation actors.

## Visibility and performance contract

- Enter distance: 38 m; exit distance: 44 m (6 m hysteresis).
- Fade: 0.35 s using per-instance `GeometryInstance3D.transparency`.
- Population: Off 0, Low 4, Medium 10, High 18; absolute cap 24.
- Simulation: fixed 0.125 s tick, backlog clamped to four ticks.
- Existing visual LOD remains 30/8/1 Hz at near/medium/far distances.
- No RPC, multiplayer state, collision actor, navigation agent, or global per-frame path search is introduced.
- Every pooled fallback shares geometry but has a stable provider-derived tint and height. Full catalog avatars are capped at four nearby identities; the fallback is intentionally less detailed and does not reproduce all clothing/accessory silhouettes. No per-frame mesh generation occurs.
- Walls provide ordinary depth occlusion; culling no longer depends on crossing a hall/room trigger.

## Validation

`tests/campus/student_behavior/test_student_behavior.gd` covers population bounds, lifecycle states, desynchronized timers, valid in-room work points, real-door inclusion, finite movement, and invalid deltas. `test_visibility_contract.gd` covers identity/motion continuity across a zone boundary, hysteresis, non-binary exit fade, and zero network traffic.

These tests are staged for the normal isolated Godot test runner after the active-play hold ends. Only offline source/layout checks were performed in this task.

