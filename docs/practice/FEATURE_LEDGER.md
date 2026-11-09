# Supported features and evidence ledger

Baseline: immutable source snapshot J (`snapshot-20261104-10`), manifest SHA-256 `2a1b3b9fc6129c6e49ab1a6f90d06674999c3e10bee3426622e731fed907ef73`. J remains the historical baseline; this v3 delta also records the actual integrated hands v1.3 and archive v3.3 modules in current Main, with separate source hashes. Eight focused current-Main archive suites now pass, including the bounded history fixture; broader Main/user-flow acceptance remains open. This is a documentation handoff; it changes no gameplay or compiler policy.

**Implemented** means present in inspected source. **Verified** below means an existing receipt reports the stated fixture passed, within its scope. It does not mean every UI step in the quick-start was replayed. **Deferred** means outside deadline acceptance. No engine, render, import, compiler, network-boundary probe, OS probe or process inventory ran in this documentation pass.

| Feature | Implemented / source-supported | Existing verification and practical limit |
|---|---|---|
| DC breadboards | 10/20/30/40 rows, grouped strips, split P/N rails, B1–B4 mappings, validation and deployment | Current J checkpoint reports 17 core groups plus four economy scenarios PASS; earlier named electrical/instrument receipts remain historical supporting evidence. The exact new quick-start sequence has source review only. |
| DC instruments | Three isolated 0–30 V channels, four current sources, finite impedances, CV/CC, meter/fuse, generator, scope | Existing instrument regression PASS is limited to its fixture; no instrument calibration claim. Generator teaching range is 0.1–100 Hz. |
| AC rack practice | Physical cable connections, bank switches, meters and generated course cable lists | Primary progress records 40 beginner-instruction cases using the actual solver, and upper-panel inspection/raycast/save/reload PASS. This is recorded coordinator evidence, not a new walkthrough. |
| Custom IC / PCB | Saved circuit composition, physical pin maps, revisions, material purchase/crafting, routed copper and standalone PCB | Current Main J physical PCB workflow: 152 checks / eight captures PASS, actual editor gestures, deploy/wire, physical pickup, place and reconnect; result records stable source, phase code 0 and normal engine exit. The earlier table-center ray obstruction is not the current outcome. Earlier Uno lifecycle/composition receipts retain their limited scope. The new two-pin resistor guide remains source-reviewed only; this is not full mouse-control coverage. |
| Core-practice J2 | **UNACCEPTED** exact-J fixture, separate from current Main hands/archive integration. | 57 checks with one failure: actual profile save/reload did not preserve the expected pin IDs/order and crafted inventory. Instrument/logic/package stage data are partial evidence only. No complete practice/restart or full mouse-coverage claim. |
| Saved designs | Character-specific electronics profile, automatic board saves, explicit package saves, saved view configuration | Save paths and error handling inspected. A local source review cannot certify a new full restart/persistence walkthrough. Active station state is not promised to resume. |
| LVScript | Educational LV Micro interpreter, templates, validate/upload/run/stop/reset, debugger and serial tools | Included in existing regression coverage; the guide's LVScript steps were not dynamically replayed here. LVScript is a separate language/backend. |
| Precompiled native | Uno R3, classic ATmega328P Nano and Pico target schema/pin maps and host-owned execution controls | Existing genuine compiled Uno lifecycle fixture PASS. Nano/Pico presence in source is not evidence that every image/peripheral works. Broad commercial/native compatibility matrix is deferred. |
| C/C++ source compilation | Source editor and broker frontend exist; strict local acceptance gate remains in force | **Deferred / unavailable for this deadline.** No trusted passing acceptance receipt is established by the reviewed progress. Do not enable compilation, weaken isolation or issue a receipt from this documentation work. |
| Cooperative work | Host-authoritative practice and shared circuit state | Existing current Main team host/client run PASS (record/repair/submit/persistence/exactly-once reward); eight-player fixture reported PASS. These do not establish full-campus 60 FPS. |
| Receipt migration / archive / cleanup | **RETAINED; archive v3.3 source integrated into Main.** Known-v1 backup/migration, bounded active receipts, checksum archive and hot/cold lookup. | Existing isolated actual-engine evidence: 118 file/migration + 138 production integration + 59 limits checks; three real owned-process termination/reopen phases, 42 recovery checks each. These are scoped private acceptance results. Immutable-head packing is now integrated. All eight focused current-Main archive suites PASS in 38.125 s, including history under its unchanged 18 s cap. Existing-schema-2 partial-head crash recovery separately passed 49/49/50 checks. Broader Main/user-flow and performance acceptance remain open; no power-loss/OS-crash or long-soak certificate. |
| Interaction hands v1.3 | **Source integrated.** Cosmetic cable/control feedback follows accepted host actions; low/right first-person pose, third-person ArmR rig binding and lifecycle cleanup. | Existing private transitive parser, 70 module/domain and 17 actual-Main fixture checks PASS; five captures reviewed by primary. No real ENet remote-gesture/reconnect or performance acceptance yet. This does not establish every control/mouse gesture. |
| Complex unsupported chip functions | **DEFERRED** for this deadline. | No blanket MCU/chip completion or full native-peripheral compatibility claim. |
| Performance and broad devices | Final three aggregate dc_lab spans integrated at b3d2 SHA; K phase-8 data valid, target **NOT MET**. | K recorded DC 21.6994 and AC 25.1091 callbacks/s. These are callback/wall-time observations, not presented FPS/GPU measurements. K predates immutable-head packing. Full-device matrix, OLED wall time and full-campus 60 FPS remain deferred/unverified. |

## Internal receipt meaning and current acceptance

Per-account operation receipt maps retain operation IDs with request digests; global trade receipts retain decisions, request data and delivery/profile snapshots. The integrated archive preserves known-v1 byte backups, immutable checksum-verified history and deduplication before publishing an atomic ledger reference; it does not delete inventory, and profile reward/applied IDs remain retained. Active maps are bounded while total disk history remains. New immutable heads pack at most 64 records / 8 MiB while preserving older committed roots and old blob bytes; no archive blob is deleted. The focused current-Main history regression now passes, but this does not certify latency for previously fragmented chains, long histories or all user flows.

## Model limits to check before choosing an IC

The **Components** catalog's rating text and pin list are the starting point. Search by component or pin name; hover the component choice to see its rating. A catalog name is not a promise of all manufacturer behavior. Custom packaging retains the underlying device models and budgets.

| Model family | Source-declared boundary |
|---|---|
| Basic parts | Ideal R/C/L approximations; resistor rating checks are not thermal damage. Silicon diode is piecewise linear, without avalanche. LEDs need series resistance. |
| 74HC gates, 74HC74, 74HC595, NE555 | Behavioral models with finite supply ranges, 40 Ω outputs and 0.5 ms update/resolution where stated; not silicon timing accuracy. |
| Educational op-amp | Rail-limited DC amplifier; no bandwidth, slew-rate or supply-current model. It is not a commercial op-amp model. |
| LV Text Display / LV graphic / LV RGB | Educational protocols. LV Text Display is not HD44780; LV graphic is not SSD1306; LV clocked RGB is not WS2812. Choose the explicit commercial entry if needed. |
| HD44780 | Bounded 4/8-bit, DDRAM/CGRAM and busy/address handling; original glyphs. Do not assume a copied manufacturer's character ROM. |
| SSD1306 | Bounded I2C addressing/display-command implementation, 1024-byte GDDRAM; external pull-ups and reset matter. Full command/timing compatibility is not accepted. |
| ILI9341 | Mode-0 four-wire SPI and supported RAM/display commands; readback, gamma, scrolling and parallel modes are not implemented. |
| XPT2046 | SPI 12-bit touch axes/pressure and PENIRQ; no temperature/battery ADC, 8-bit or pipelined modes. |
| WS2812B | Eight-pixel legacy GRB/timing model; submicrosecond electrical edges required. A slow educational clocked strip is not a substitute. |
| PCA9685 | Selected I2C register/PWM/external-clock behavior, not unrestricted chip coverage. |
| Native boards | Board-specific engines and pin maps. Pico boot ROM, USB, second core and MicroPython unavailable. Native SPI/I2C controllers operate as masters; MCU slave mode and 10-bit I2C unavailable. Additional CPU families require genuine engines and pin maps. |
| Custom composition | Maximum 48 direct parts, 96 wires, 1–64 package pins, eight nesting levels, 128 traversed nesting nodes, and 64 expanded components. Board limits also apply; wrapping components in an IC does not bypass them. |

## Current J proof scope

The current checkpoint record reports 17 core groups and four economy scenarios PASS. The PCB fixture reports 152 entries: its phase list contains 144 passing assertions and eight capture metadata records; the result records source stability, phase code 0 and a normal engine exit. Some fixture messages retain their historical H-v6 names; the result provenance identifies the actual run as current Main J. This is a bounded physical workflow result, not whole-game performance, all mouse gestures, every MCU feature, or receipt-archive acceptance.

## Evidence provenance

Hands v1.3/archive v3.3 integration and scoped acceptance receipts, current J/PCB evidence and historical supporting evidence are recorded with hashes and extracted statuses in [evidence.json](evidence.json). They are review receipts, not files the player needs to install.

- `current-regressions/result.json`: inspected existing named fixture statuses; no rerun.
- `final-native-1793843403507450300/result.json`: three existing fixture PASS statuses; no rerun. Detailed 21/four/lifecycle scope comes from `PRIMARY_CURRENT_FINAL_ACCEPTANCE_PROGRESS.txt`.
- `PRIMARY_CURRENT_MAIN_ACCEPTANCE_ADDENDUM.txt`: eight-player and regression context, historical compiler failure context; its historical next-step suggestion is superseded by the explicit deadline deferral.
- Historical snapshot H metadata: subsequent metadata/wire-expansion optimization verification is described there as current strict 14 regressions and real native/composition/PCB PASS. No solver-factorization cache or blanket performance proof is claimed.

## If the example does not work

Check the equipped kit, owned stock and deployment status first. Confirm B1/B2 mappings were committed with Enter and that resistor legs occupy different electrical groups. Check both rail halves when using rails. Then check master and per-source enable settings, a complete return lead, meter mode/range and fuse. Current measurements need a series path; voltage measurements need parallel leads. Turn outputs off for resistance/continuity/diode tests and isolate a capacitor for capacitance tests. Read the displayed validation/solve error instead of accepting an invented measurement. Source compilation being unavailable is expected for this deadline; use LVScript or an already validated precompiled image for the supported board.

## Latest focused Main archive acceptance

`PRIMARY_MAIN_ARCHIVE1_RESULT.json` records all eight suites accepted on stable current source in 38.125 s: 268 history checks (unchanged 18 s suite cap), paid-outcome, 118 migration, 138 integration, 59 limits, 191 old-root, 272 record-boundary, and 99 large-byte/full-record checks. The earlier three known-v1 migration termination/reopen phases (42 checks each) are distinct from the later **existing schema-2 partial-head replacement** tests (49/49/50); neither is an OS-crash or power-loss certificate. Broader core/multiplayer/course/restart coverage remains open, with the specific J2 profile-reload failure retained above.
