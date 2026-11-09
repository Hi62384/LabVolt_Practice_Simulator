# LabVolt Cooperative Laboratory

For step-by-step AC/DC breadboard and custom-IC practice, see [Practice quick-start](docs/practice/QUICK_START.md). The [feature ledger](docs/practice/FEATURE_LEDGER.md) separates implemented behavior, existing verification and deadline deferrals.

Run **Run.cmd** in this project folder. It uses the bundled Godot runtime; older exported executables do not include these changes. F11 or Alt+Enter toggles fullscreen.

## Start a session

Choose **Host Game**, select **Freeplay** or **Class**, and select difficulty. Leave **Play alone** checked for single player; uncheck it for multiplayer. On a second instance on this computer, choose **Join Game**, address `127.0.0.1`, port `24842`. Use a different saved character/profile on each instance to maintain separate grade records. LAN players use the host computer's LAN address and matching UDP port.

The main menu has a character portrait gallery, in-window cartoon character studio, and settings. In the lab, Escape opens the in-game menu. Multiplayer continues while a menu is open.

## Teacher and papers

- **Right-click the instructor** for a topic, random assignment, or guided practice lesson. Difficulty changes numerical complexity; advanced series work also adds circuit elements.
- **B** reads the paper you are carrying.
- **Right-click a clear tabletop** to place your paper. **Click/E** picks up your own placed paper; **right-click** reads anyone's placed paper.
- Use the page arrows, answer fields, drawing area, and calculator. Answers and drawings stay with the paper as it moves. Its tabletop face displays the last page its owner viewed.
- Only the owner can write or pick it up. Other readers see updates and have read-only access.
- Carry an assignment to the instructor and choose **Hand in held assignment**. The marked paper is returned with question-by-question feedback. Each submission contributes once to the profile's saved arithmetic-average mark.
- Lessons and late-arrival practice sheets can be checked for feedback without affecting your saved average.
- Carry an unwanted sheet to the **PAPER** recycling bin near the rear-right wall and right-click it.
- Select an active item using the six-slot hotbar. Store and organize larger collections in Electronics · Shop & Kits.

Numerical and multiple-choice answers are automatically marked. Freehand workings are saved notes, not automatically assessed. Numeric fields use the printed unit when no suffix is supplied. Course questions also accept compatible unit suffixes, such as mA or kΩ; the marker checks dimensions and stated tolerances. The scientific keypad has DEG/RAD modes, trig/inverse trig, roots, powers, brackets, Ans, and memory. It starts in DEG mode. The paper tools include a pencil with preset/custom colors, an eraser, movable text and equation annotations, and answer fields. Text can be rotated, resized and baked into the page. Page, scroll and zoom are restored when you reopen the sheet. Lessons contain equipment instructions and worked calculations followed by three practice questions; Check practice provides corrections without changing your profile average. Try again reopens practice answers.

## Class mode

Each legacy Class round has a five-minute whiteboard lesson, followed by a shared lab assignment and a 30-minute deadline. Campus course activities use their own lesson and assessment schedule. Mathematics assessments give each student an immutable individual numerical version; reconnecting or replacing a sheet does not reroll it. Submit to the instructor before time runs out. At the deadline, completed answers are marked and unanswered parts receive no credit. When everyone submits, or the deadline expires, there is a one-minute break and a new round begins.

Joining during the lesson includes you in that round. Joining during the assignment gives ungraded practice; your graded participation starts next round. Disconnecting removes your physical sheets. Rejoining the same live host with the same profile restores your current Class work and its original deadline. Leaving does not extend the original deadline. The host retains your current work and delivers completed marks on reconnect. Selected campus courses have a host recovery journal. Choose the character that hosted the class, then **Resume Saved Class** on the main menu; choose single player or reopen its multiplayer port. Students rejoin using their saved profiles to reclaim their work. If the authority was unavailable past the assessment deadline, the unresolved attempt is voided without an official penalty. The legacy repeating Class mode does not provide the same host-restart recovery. There is no mid-round host migration.

Freeplay sheets are discarded on disconnect. A Class replacement sheet can be requested from the instructor if the active sheet was trashed. Trashing Class work does not cancel its deadline.

## Bench and room controls

WASD moves, mouse looks, Shift runs, Ctrl crouches, Space jumps or stands from a chair. Click a chair to sit. WASD pushes the chair; opposite-direction input brakes. Mouse movement adds swivel momentum, and opposite movement brakes the spin. Chairs accelerate gradually and coast.

Open the cable drawer beneath any of the three benches. Click a color bag to take a lead. Click terminals to connect; up to **12 plugs** stack at one terminal. Parallel leads and both ends of a cable on one post are allowed; each end uses a stack slot. Right-click/Q unplugs. **G** puts down a held cable; **Backspace** returns the entire held cable. Freeplay allows wiring changes while powered. Marked training circuits enforce their stated power-off procedure. Drag or wheel on the variable control changes output. The supply knob covers 0–100%, including while energized. Click/wheel the small selector to change the AC voltmeter circuit. Drag/wheel the dynamometer knob to vary load; hold E/click on its measuring control for speed and torque. Supply reset buttons turn off/reset the supply without deleting wiring. C checks wiring, P switches power. The prompt shows the action available under the crosshair.

Click the DAQ's USB control to open its four RMS voltage and current channels with phase angles. Voltage channels connect across nodes; current channels go in series. The transformer has the photographed 1–2, 3–7–8–4, and 5–9–6 tap arrangement and an ideal coupled-winding model.

## Close-up equipment view

Aim at an AC equipment panel and press **F** for a straight-on inspection view. This lets you read the upper instruments without changing your character's height or squeezing the bench layout. Scroll to zoom; your view is restored the next time you inspect that panel. Press F or Escape to return to walking.

## Team troubleshooting

In Freeplay, press Escape and open **Team troubleshooting** with two to eight players connected. The host chooses a troubleshooting project. Read your assigned role, record the original fault using the real instruments, choose a diagnosis, turn the supply off to repair it, run preflight, and record the corrected circuit before submitting. Each participant's actions supply the team's evidence. Completed results and rewards are saved together; repeating the same project seed does not award duplicate money or mastery. Earned plaques can be placed on the fixed honours mounts above the AC racks.

The instructor also offers a host-only **Earthing demonstration** outside formal coursework. Choose an isolated source or an explicit neutral-to-earth bond and optional chassis fault. This uses finite-resistance paths and the actual AC solution. It requires an AC bench without external links; starting formal coursework clears it. It is an educational demonstration, not a certified electrical safety model.

## Character profiles

Click a portrait to select a character. Create Character or Open Character Editor opens the original LabVolt cartoon studio inside the game window. Choose a starting look, then edit body proportions, face, hair, outfit and colors. Drag the preview to rotate, scroll to zoom, and use Face for a close-up. Save character returns to the gallery; Cancel preserves the previous save. Existing profile names and identities are retained when converting older appearances. Duplicate creates an independent profile.

Profiles, exported appearances, selected profile, and grades are stored in Godot's local per-user application data, separate from the project. A second simultaneous instance of the same profile is assigned a guest identity to avoid shared grading ownership. Character appearance changes during a session do not change that session's grading identity.

## Campus and electronics

Open **Campus · Courses & Map** for Freeplay, Open Lab and formal course activities, the room directory, floor maps and saved course progress. ELM253 and ETY155 have lecture and laboratory work with separate marks. MTH147 and MTH255 are lecture-only mathematics courses in the existing classroom, with structured equation, graph, geometry and data widgets. Calculator and formula-reference access follow the host’s assessment policy; guided practice permits learning tools and never changes official averages. The host starts shared activities; room slips identify your destination and assigned bench. The lift connects the floors. Facilities include a gym and food counters with persistent purchases and activity rewards.

Open **Electronics · Shop & Kits** for owned parts, kits, notebooks, breadboards, custom ICs/PCBs, programming, the live analyzer and trading. The six-slot hotbar holds carried items; larger collections stay in the manager. Deploying a build consumes/reserves actual owned stock. Returning a build restores its owned parts rather than duplicating them. Selected physical resistor units retain their manufactured resistance and rating through recall and trade.

The three DC stations have independent triple-channel supplies, four adjustable current sources, function generators, meters and oscilloscopes. Source outputs and scope traces come from the electrical solve. Each oscilloscope has independent channel settings, trigger controls, recording and cursors. Routed PCB traces and editable board outlines affect actual connectivity and manufacturing validation. AC/DC links include supplies, passive banks, instruments, DAQ and transformer coupling. Practical course work checks the real circuit and measurements at the assigned bench.

Native Uno R3, classic ATmega328P Nano and Pico devices accept validated compiled machine-code images through the in-game Code page. Source drafts, upload, run/stop/reset/step, breakpoints and serial inspection are available. Execution is host-controlled and connected to actual circuit GPIO/ADC. SPI modes 0–3, 7-bit open-drain I2C and electrically serialized UART use the shared circuit timeline. LabVoltScript remains a separate educational backend. The source compiler frontend and isolated Windows broker are installed, but source compilation stays disabled until the local compiler passes all trusted boundary and runtime checks. Editing/saving source and importing images remain available; there is no unrestricted compiler fallback.

## Scope and model limits

This is an educational simulator with procedural equipment. Device models have documented finite budgets and approximations, rather than manufacturer-calibrated SPICE fidelity. AC steady-state machine models do not constitute a full motor/inverter switching-transient simulation. Resistor overrating is reported from solved power; thermal damage is not modeled.

Native instruction execution does not imply complete peripheral compatibility. Pico boot ROM, USB, second core and MicroPython remain unavailable. Native SPI/I2C controllers currently operate as masters; MCU slave mode and 10-bit I2C are not supported. Commercial models implement bounded subsets for HD44780, SSD1306, ILI9341, WS2812, PCA9685, XPT2046 and selected oscillator/quartz/op-amp devices. Unsupported commands and timing/analog limits remain explicit in their catalog entries. Additional CPU families require their own genuine engines and pin maps.

Course sources guide topics, difficulty and diagram conventions. Assessed calculation scenarios are generated from seeds with verified answer keys rather than copied source answers; worked teaching examples are separate. Representative diagrams and generator invariants are checked. Cases that require unavailable hardware remain gated. Host-led inventories are authoritative within that host; this is not a global account service or protection against a malicious host. Selected campus courses recover from the host journal as described above; legacy repeating Class mode and mid-round host migration have different limits. Long-running save-contention/receipt-compaction soak coverage is not claimed.

## Validation

Run `python tests/run_tests.py --godot "path/to/Godot_console.exe" --visual` for electrical, gameplay, UI, school, instrument, and multiplayer regression checks. `tests/school_network.gd` is an additional two-process reconnect/grade test (`host` and `client` roles, port 24919). Tests use accelerated Class time rather than waiting 36 minutes.
