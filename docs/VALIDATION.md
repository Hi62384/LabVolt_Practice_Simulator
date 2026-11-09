# Integrated source checks — 4 November 2026

The current editable project is the existing `Documents/GodotProjects/LabVolt_Practice_Simulator` folder. Run `Run.cmd`; earlier standalone exports are historical. No new export/archive was produced for this revision.

The final combined run passes all 14 suites: electrical, instruments, extended room/chairs, school, new features, campus integration, facilities, academics, independent current sources, native programming, physical resistors, owned EEPROM, I/O epochs and public-device state. The corrected school acceptance checks current practice policy separately from exactly-once official grades. Raw logs and machine-readable results are retained in `validation_logs/integrated-20261104`.

Additional checks pass:

- Real eight-process ENet session: host plus seven clients, independent controls/state convergence, public-profile privacy and simultaneous disconnect cleanup. No unexpected engine/script errors.
- Actual Main native-device upload through the normal host route, physical header/LED circuit, real instruction cycles, Stop/Resume, power-loss high-impedance GPIO and owned-child cleanup.
- Independent current-source channels 1 and 4 respect the bench master isolation and retain 0.5 ms stepping when energized; the actual resistor voltage is checked.
- Actual Main socket optimization: 399 sockets batched; 1197 socket instances saved. Fine-detail shadows restore original cast flags. Rendered rack and close-up inspected after the startup-order fix.

A source-stable 1080p, 4×MSAA fixed-view comparison measured 45.294 process callbacks/s with fine-detail shadows on and 56.251/s off; the off sample had a 38.995 1%-low rate and 23.740 ms p99 interval. Neither 15-second steady sample contained a ≥100 ms interval. These are bounded fixed-view measurements, not a 60 FPS or full-campus performance pass. Startup still contained roughly 3-second and 1-second stalls with cause unassigned. Profiling evidence V8 also records an orchestration-window overrun; it is not claimed bound-compliant. Earlier withdrawn V7 data is excluded. The V8 source manifest records the exact historical measured revision; later tests and documentation are separate.

Only the known Godot certificate-store diagnostic is accepted. Other engine errors, script errors, assertion failures and nonzero exits fail the checks. Native/peripheral/model limits are documented in README.md. Multiple-machine WAN play, packet-loss stress, long-running save contention and complete hardware peripheral compatibility remain unverified.

---

The record below is historical baseline evidence, not the current revision's feature or verification list.

# Validation record

Test environment: Windows, Godot **4.5.1 stable official f62fdbde1**, OpenGL Compatibility renderer; rendered gameplay used an NVIDIA RTX 3060 Laptop GPU. Tests ran against actual Godot processes, not a separately rewritten solver. The entry scene was imported, executed, rendered, exported, and the resulting standalone executable launched.

## Automated evidence

| Suite | Result | Scope |
|---|---|---|
| Electrical/domain | 77 assertions, zero failures | Balanced Wye/Delta, line/phase quantities, unequal loads, open-neutral star displacement/KCL, L/C phase and reactive power, series RLC, correction/PF, balanced and unbalanced three-wire two-wattmeter relationships, floating ideal source, isolated networks, singular conflicts, finite meter loading, frequency, source/ammeter short protection, cable ownership, end release/reclaim, stale switch races, host permissions, safety and exam grading |
| Rendered gameplay | 24 assertions, zero failures | Unwired startup/menu, CharacterBody3D, floor, jump/gravity, real rack pickup, crosshair ray targeting, individual plug ends, actual switch/power interactions, 12 W physical circuit, removal/reset, zoom, knob drag, workstation collision, WASD/crouch, visible remote avatar and crouch interpolation |
| ENet host | 7 checks, zero failures | Real server; client wire creation; host solve of cross-player circuit; parity confirmation; late-state confirmation; installed cable retention; carrying-player disconnect release |
| ENet client | 6 checks, zero failures | Real client/roster, host switch/power updates, authoritative reading parity, cross-client cable state |
| ENet late client | 4 checks, zero failures | Real late connection, existing cables/switches, energized readings, host-shutdown handling |
| Standalone Windows smoke | Exit 0 | Exported executable initializes the actual game scene and runs 180 frames |

Total: **118 automated assertions/checks**, all passing. Logs are retained in [validation_logs](validation_logs). The electrical solver uses independently calculated analytic references rather than checking only its own formulas. The motor torque comparison uses a separate Thevenin equivalent expression. Reference tolerances are visible in the test source.

The multiplayer tests launch three independent OS processes on a loopback UDP port. They do not merely call RPC handlers directly or substitute an offline multiplayer peer. Domain tests separately verify deterministic conflict/lock behavior. The visual test creates avatar geometry from a replicated-pose payload; two simultaneously rendered multiplayer windows and human hand interactions were not evaluated.

## Rendered inspection

The rendered previews are [menu_preview.png](menu_preview.png) and [laboratory_preview.png](laboratory_preview.png). Visual inspection caught and corrected an occluding cabinet face. Game-level testing caught a test-target issue caused by the live raycast updating between scripted interactions; tests now aim each interaction explicitly. Numerical tests caught loss of shunt-current precision, which was repaired by calculating current from float64 node differences before phasor conversion.

## Environment diagnostic

Godot prints **“Failed to read the root certificate store”** under this restricted Windows execution environment, including in otherwise successful empty/headless starts. It is an engine initialization diagnostic, not a parser, project-script, scene, OpenGL or ENet failure. The game uses UDP ENet rather than TLS. The runner permits exactly this known line and still fails on other ERROR/SCRIPT ERROR lines, failed assertions or nonzero exits. This diagnostic is retained in the raw logs rather than concealed.

## What is not verified

Exact correspondence to the physical station's meter internals, motor nameplate or calibration; real protective device timing; real-world wiring safety; eight-player load/performance; multiple computers or WAN/NAT/firewalls; packet-loss/latency stress; long sessions; every key rebinding combination; audio perception; multiple GPU vendors; and all manual acceptance combinations. Use TEST_CASES.md for repeatable further verification. No claim of complete commercial polish or manufacturer-certified accuracy is made.
