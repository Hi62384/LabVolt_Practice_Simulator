# LabVolt remaining-work audit

This page tracks the Windows game and the checks that support its current status.

| Area | Current evidence |
| --- | --- |
| Campus OS and Chromium | The rendered workstation fixture checks native website buttons, direct links, confirmation, exact PDF and PNG contents, the 8 MiB limit, and powered-off cleanup. A two-instance test checks a large download and copying it to a remote USB drive. The native Chromium fixture checks the right-click menu and inspects the clicked input. All eight installed apps were rendered from the public workstation and compared with the Campus OS concepts. The workstation now suspends rendering the covered 3D world and restores the room view on exit. |
| AI lessons and assessments | The classroom event gate is enabled. The local API fixture exercises class connection verification, a scheduled instructor moving during the lesson, and separate room and scheduled assessment paths. Both lab instructor routes and all five lecture rooms passed their in-game checks. The scheduled instructor and room instructor now use the same movement code. |
| Teacher voices | The bundled Piper test generated audible, distinct WAV data for all 21 teacher profiles. A live classroom test verified that speech playback was attached to the instructor and stopped at teardown. |
| Classroom attribution and Invention Studio | The thrown-object reaction and live invention rubric tests passed. Articulated inventions and chained hinges were implemented in earlier commits. |
| Campus rendering and gym | The Forward+ graphics and display check passed, including the Main panorama and SDFGI setting. The lighting test passed for the audited lab and lecture fixtures. The campus world suite passed 175 checks. The live gym sequence passed. |
| Startup | The isolated Singleplayer and Host Game Play routes passed. |

## Remaining dependencies and limits

- A live OpenAI account request requires host credentials. The classroom integration test uses a loopback API fixture.
- Chromium packaging and gameplay checks here cover Windows x64. Other platforms need compatible renderer builds if they are targeted.
- The updated lost-and-found Worker is deployed in production (version `f6ff53a2-4740-4d08-b331-34c6fb55a872`). Two isolated game instances verified that a second host cannot reserve the same paper and cable until reopening the original ledger releases their unconfirmed awards. The original host also verified recovery of an awarded inventory item without a duplicate. Claims stranded by older builds without a receipt still require review. See the [handoff documentation](claim_authority/README.md).
- Enabling the native C/C++ toolchain requires a trusted installed toolchain and a matching acceptance receipt on the target host.
- The Forward+ Ultra tour sampled 37 locations at 1280×720 on an RTX 3060 Laptop GPU. Most views averaged about 60 FPS. The upper hallway was slowest at 57.4 FPS, with a 38.6 ms worst frame. These are stationary singleplayer samples and do not measure multiplayer load or continuous room transitions. The tour is reproducible with `tests/campus/performance/ultra_campus.gd`.
