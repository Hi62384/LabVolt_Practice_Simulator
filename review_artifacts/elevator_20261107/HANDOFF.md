# Elevator redesign — private implementation

Useful result: real private geometry, host state machine and adapter are complete, with four exact-preimage production patches. No production files were changed by this worker. `python review_artifacts/elevator_20261107/check_source.py` passes 29 source/geometry checks. Engine compilation, state/geometry execution, actual ENet results, screenshots and performance evidence remain **unexecuted**, reserved for runtime owner `01a1b280-d9b9-7520-b718-f4e04dfb4e06`. No engine, CUA, active game focus, reload, process control, live save or cache operation was performed. No action was denied.

## Integration (main owner only)

1. Preserve the exclusive directory `review_artifacts/elevator_20261107`.
2. Check `manifest.json` exact SHA-256 preimages against current shared files. Four `.preimage`, `.proposed`, `.patch` triplets are supplied for `campus_world.gd`, `campus_integration.gd`, `game.gd`, and `world_tests.gd`. Apply only elevator hunks if another owner has changed the source; do not replace a newer shared file with an old candidate.
3. Copy `elevator_state.gd`, `elevator_geometry.gd`, and `elevator_service.gd` to `scripts/campus/elevator/` with the same filenames. Godot UID/import creation is reserved for runtime owner. No imported art or device assets are required.
4. Adopt the four shared patches together. The world mounts the geometry, emits physical-control requests, and never teleports. The integration mounts the adapter **after** facilities install their movement hooks. The adapter composes those hooks and calls existing `_relocate()` for every rider. The old single-rider `_elevator_request` RPC is removed. HUD gains one physical-control prompt case. World test's obsolete single-rider-validator expectation is replaced.
5. Run the isolated, owner-guarded runtime fixtures below. Review/correct compiler and runtime output before acceptance. This handoff is not a runtime-pass claim.

## Source-bound geometry contract

Inspected current adopted `campus_world.gd`, `hallway_geometry.gd`, `hallway_finish.gd`, registry and transition/session/player services. No repository/ancestor AGENTS.md was found. The existing room identities, spawn system and navigation graph are unchanged.

| Contract | Value |
|---|---|
| Actual floor IDs / public labels | 0, 1 / Floor 1, Floor 2 |
| Existing landing Y | 0, 5 |
| Existing elevator bay | X16..24, Z56..62, both landings |
| Preserved hall aperture | X16, Z58..60 |
| Door leaf plane / thickness | X16.18 / 0.09 m |
| Closed leaf centers | Z58.5, Z59.5 |
| Open leaf centers | Z57.45, Z60.55 |
| Frame / opening height | 3 m opening, top frame Y3.04 above each floor |
| Pocket clearance | Existing hall wall ends at X16.08; door X16.135..16.225; rear pocket skin begins X16.31 |
| Cabin floor / roof | Existing floor top Y0/5; roof underside Y3.97/8.97 |
| Call control | X15.82, Y1.25+floor*5, Z60.35 |
| Cabin buttons | X16.43, Y1.48 or 1.20+floor*5, Z60.45 |
| Bench / plant | West wall X10.55, Z64.4 / Z66, beyond stair end Z62 |
| Protected routes | Original X13..16 upper route, stairs X10..13/Z50..62 and elevator Z58..60 stay clear |

Cabin is the original entire 8x6 bay, with enclosing front pocket skins, side/rear walls, floor, roof, handrails, light and actual-floor panel. Waiting furniture is outside it. New waiting ceilings cover X13..16/Z58..68 and X10..13/Z62..68 without spanning the stair ascent. Materials belong to this component; no global recolors. M101 devices/resources were not touched. Reference `libfile_93ffb230abf0819196e4b0f99bb2ae71` was not available through filesystem evidence; no claim of seeing it. User's specified campus palette/entrance vocabulary guided the design, with no central block.

## Authority and safety behavior

- One host FIFO of actual floor IDs, duplicate calls coalesced. Cabin selections accepted only fully open; landing calls queue during travel. Every request checks registered peer, proximity, control side, state, formal-activity/facility/cable restrictions and rate limit.
- Host snapshots all cabin occupants at close completion, including jumping/wall-adjacent players. It never uses only the requesting peer. Each rider retains a distinct cabin offset and uses the existing pose-epoch relocation at arrival, on reliable channel 4.
- Doorway capsule/sampling margin prevents closure; a late obstruction or ineligible cabin occupant reopens and retains the request. No force-close timeout. Full doorway barrier guards entry during closing, movement and opening. Opening completion snaps the leaves fully clear before releasing collision.
- Source cabin remains opaque and stationary during the 2.2 s synchronized transition; all captured riders are frozen. Both landing replicas are always enclosed, and the inactive entrance stays shut. No shaft physics, moving plates, continuous door-body simulation or per-frame replication.
- The timer runs at 10 Hz only while travel, door motion or a queued obstruction needs observation; it stops at open idle. Snapshots publish on state/queue/rider edges. Client initial sync retries at 1 Hz until a host snapshot; request/sync RPCs are bounded.
- Disconnect removes that rider only. Session `leaving` captures the **old** peer ID before ENet becomes offline peer 1; restart clears queue/locks and uses existing epoch relocation to ground hallway X14.5/Z59 for an interrupted local rider. Other interrupted clients recover through their own existing Session.leave lifecycle.

## Runtime owner's exact remaining evidence

Run only in the established guarded disposable project/profile. `Main.tscn` fixtures use real initialization and normal services, which may otherwise access user profiles; this worker did not run them. Commands below are Godot arguments, not authorization to focus/reload/stop the user's game.

1. Engine parse/import of the **integrated** candidate and unchanged wider project; capture errors/warnings. Existing campus world test: `--headless --path <isolated-project> --script res://tests/campus/world/world_tests.gd`.
2. Actual state tests: `--headless --path <isolated-project> --script res://review_artifacts/elevator_20261107/test_elevator_state.gd`. Checks queue/coalescing, invalid floors, late obstruction/release, all riders, moving misuse, reverse calls, eligibility, disconnect, boundary/jumping inclusion and 20 repetitions. These tests execute the real production GDScript, not a Python copy.
3. Actual geometry/tween/collision tests: same arguments with `test_geometry.gd`. Verifies both real doorway barriers, physical controls, intermediate Tween position, obstruction reversal, roof/rear-wall ray hits and traversable open aperture.
4. Actual two-process ENet fixture: same guarded project with `network_fixture.gd -- host 19277` and `network_fixture.gd -- client 19277`. Runtime owner launches/manages the two processes. Uses real Main, Session host/join, reliable RPCs, pose epochs, physical control ranges, concurrent same-stop selection, actual doorway obstruction and release, shared up/down trips, remote lock/release and moving-state misuse. Fixture host-positioning is deliberate setup through existing `_relocate`, not a replacement transport. Collect both `ELEVATOR_NET_RESULT` logs, actual peer IDs/poses/epochs and revision traces.
5. Additional real-session cases not automated in that fixture: disconnect a rider mid-trip; host interruption while moving and while opening; a third-peer remote landing call while moving; join during movement; a rider exits before capture; multiple distinct queued landing calls. Capture all affected peers' resulting poses, doors/locks and recovery. Confirm no one stays frozen or is transported from a hallway.
6. Real-renderer screenshot fixture: `--path <isolated-project> --script res://review_artifacts/elevator_20261107/screenshot_fixture.gd`. It saves entrance_open.png, cabin_interior.png, doors_closing.png, doors_closed_travel.png and waiting_area.png **only when executed**. These isolate the actual production campus shell; additionally capture in-game entrance/cabin/door screenshots from the ENet session, confirm text faces, clearances, lighting, sightlines and collision by walking through.
7. Measure representative idle/door/travel frame time and snapshot counts with 2–8 real peers. Validate unchanged hall/stairs, room access, spawn, HUD/hotbar and M101 behavior. Generated tiny PCM cues need listening QA; no imported audio files are required.

Artifacts currently contain no generated screenshots, network passes, engine logs or fabricated acceptance results. Remaining execution is pending the designated runtime owner, not blocked by a denial.
