# Facial compositor verification

## Changes and confirmed causes

The two eyes are now constructed with the same explicit `EyeL/Blink` and
`EyeR/Blink` hierarchy. Previously, duplicate mesh names were used to identify
parts during reparenting. Godot renames duplicate sibling nodes, so the second
eye's meshes could remain outside their intended parent. Initializing the
expression rig during a blink also captured a partially closed scale as its
rest. The new rig stores authored rest transforms at construction and keeps
blink on a child pivot, separate from the emotion transform.

Brow segments and glasses have explicit semantic roles. The previous brow
coordinate filter also selected upper glasses segments. Both brow endpoints
now rotate around the same anchor, retaining their lengths instead of shearing
them by different amounts. The head's procedural animation track is disabled
only when the expression compositor takes ownership; normal player avatars
retain that track when they are not using the NPC compositor.

The new `character_face.gd` owns speech aperture and mouth visibility. Resting
grin teeth are a fitted flat strip and disappear during a frown or active
speech. Audio ending restores the current expression without exposing old
teeth or the lips hidden by a replacement cosmetic face. Facial expression
code no longer uses mesh-coordinate guesses.

## Executed checks

The final native campus follow-up below is the most complete integration check.
The first table records the original isolated comparison, retained so the
original facial defects remain visible independently of campus materials.

| Check | Observed result |
| --- | --- |
| Facial compositor geometry and ownership suite | **PASS**, 4,782 assertions; 4 glasses styles × 3 eye proportions; seven moods; 180 animation frames per appearance; speech start/stop; cosmetic hide/restore |
| Existing `test_teacher_speech_player.gd` | **PASS**, real production queue, priority, cancellation and mouth lifecycle |
| Native baseline renderer, source `7ec6c95241fca70e724783d6234dc3f445a6630c` | **PASS**, 12 visible cases, 1280 × 1060 output |
| Native updated renderer | **PASS**, same 12 cases and camera/lighting setup |
| Script or engine errors in isolated verification | **None**; the software renderer reports unsupported V-sync; the baseline also reports two leaked ObjectDB instances at exit |

The images were rendered by Godot **4.7.2**, X11, OpenGL compatibility, Mesa
llvmpipe. They were visually inspected after generation. The baseline image
visibly reproduces the single-eye blink, distorted upper glasses, unequal brow
segments and white grin geometry above the angry mouth. The updated image
shows matching eye closure, rigid glasses, anchored brows, and no protruding
teeth during anger or speech.

- [Baseline native render](facial-before.png)
- [Updated native render](facial-after.png)
- [Source hashes, exit codes and measured run times](facial-verification.json)
- [Baseline renderer log](facial-before.log)
- [Updated renderer log](facial-after.log)
- [Facial assertion log](test_character_facial_compositor.log)
- [Speech player assertion log](test_teacher_speech_player.log)

The measured test durations were 0.663 seconds for the assertion suite,
0.255 seconds for speech lifecycle checks, 1.961 seconds for the baseline
render and 1.622 seconds for the updated render. These are complete probe
execution times on this environment, **not** a controlled gameplay frame-rate
benchmark or evidence of a general performance gain.

## Native campus integration and an additional confirmed defect

The actual `Main.tscn` scene was started through Singleplayer with the built
Godot **4.5.1 Mono** runtime. The probe selects the real faculty models for
Mr Bro and Dr Volts and uses a close-up diagnostic camera. The actual campus
lighting, material settings, geometry, expression compositor, animation tracks
and speech player remain in use. Routine movement is paused so a specific
animation frame can be photographed; the shared school-world locomotion driver
is also paused, since it correctly resumes paused idle animations otherwise.

The initial campus renders exposed **black face, hair-cap and clothing meshes**
which the original isolated scene did not reproduce. The same issue reproduced
at baseline `7ec6c95241fca70e724783d6234dc3f445a6630c`. Controlled comparisons
isolated the trigger to the campus material policy's anisotropic filtering:
material duplication and visibility distance alone rendered correctly, while
filtering alone reproduced the black surfaces. The generated elliptical meshes
had no UV attributes. Providing continuous UVs fixes the material path without
changing lighting or graphics quality. The generated speech aperture now has
UVs for the same reason. The updated isolated renderer applies this real campus
filtering policy too.

| Final check | Observed result |
| --- | --- |
| Facial compositor and UV regression | **PASS, 4,878 assertions**, zero failures |
| Speech lifecycle regression after UV change | **PASS** |
| Native campus-filter baseline and updated matrices | **PASS execution**, 12 cases each; baseline reproduces black surfaces; updated image visibly resolves them |
| Actual Main-scene faculty captures | **PASS**, 18 images; nine states each for Mr Bro and Dr Volts |
| Blink frame ownership in Main | Both authored blink pivots remain closed before and after the capture frames |
| Actual playback and stop | Both teachers receive an accepted audio stream with a unique serial; speech aperture and subsequent angry resting expression are separately captured |
| Existing modern-body deformation runtime smoke | **PASS**, all 14 parameter extremes; no new tangent-generation or animation-path errors |

All 18 final Main captures were visually inspected. The states are neutral,
happy, angry, sad, tired, excited, angry during a blink, sad during speech, and
angry after speech stops. Dr Volts' uncovered eyes visibly close symmetrically.
Both teachers retain their glasses geometry and anchored brow lengths, show
appropriate mouth and head changes, and restore the current expression after
speech. The separate grin cases demonstrate suppression of resting teeth during
anger and speech. Mr Bro's sunglasses naturally obscure most of his eyelids.

- [Final matrix using campus filtering](facial-campus-filter/facial-after.png)
- [Baseline matrix using the same filtering](facial-campus-filter/facial-before.png)
- [Final 4,878-assertion log](facial-campus-filter/test_character_facial_compositor.log)
- [Final isolated source hashes and timings](facial-campus-filter/facial-verification.json)
- [Actual Main: Dr Volts, angry blink](in-game-faces/dr_volts-blinking_angry.png)
- [Actual Main: Dr Volts, sad speech](in-game-faces/dr_volts-speaking_sad.png)
- [Actual Main: Mr Bro, angry](in-game-faces/mr_bro-angry.png)
- [Baseline Main: black face and clothing](in-game-faces/baseline-mr_bro-neutral.png)
- [All 18 captures and actual model paths](in-game-faces/in-game-faces.json)
- [Main execution result](in-game-faces/result.json)
- [Capture and production-source hashes](in-game-faces/capture-manifest.json)

The final full-scene capture run took **34.416 seconds** for game execution and
**40.609 seconds** including the harness. It used X11, OpenGL compatibility and
Mesa llvmpipe software rendering. These durations include scene construction
and all 18 captures; they are not response-latency or GPU-performance metrics.
The only engine errors were the same three unavailable Windows-only CEF
extension messages seen on the unchanged Linux baseline. There were no script
errors or unexpected engine errors in the successful final run.

## Reproduction

With a desktop display available:

```sh
python3 tests/campus/academics/run_character_facial_checks.py --native \
  --baseline-ref 7ec6c95241fca70e724783d6234dc3f445a6630c
```

The runner copies the actual production modules and their preload dependencies
into a temporary project, records SHA-256 hashes, and isolates Godot user data.
It does not replace the facial code with mocks. This avoids loading the game's
Windows-only CEF browser extension during the modular checks. Use `--godot`
for a different executable. `--xorg-display 28847` was used here to start a
temporary Xorg dummy display inside the execution environment; this is only
needed for an isolated environment without an existing desktop.

For the actual Main-scene captures, build/import the Mono project and use the
same isolated startup harness described in `tests/menu_startup/HANDOFF.md`, with
these additional arguments:

```sh
--native --script tests/campus/academics/render_character_in_game.gd \
  --expected-pass 'IN_GAME_FACES PASS' --timeout 160
```

Supply the harness's required `--godot`, `--wrangler` and `--output` paths, plus
`--dotnet-root` when the SDK is not on PATH. The output directory contains the
18 PNGs and `in-game-faces.json`. The harness now stops promptly on a GDScript
error rather than waiting for the scene's timeout.

## Boundaries of this evidence

The isolated images are dedicated-scene renders; the added campus images use the
actual Main scene and faculty models. Both use explicit diagnostic emotion and
animation inputs, so they do not prove AI-generated emotional decisions. The
voiced renders use a generated audio fixture to exercise the actual playback and
mouth path; they do not prove live TTS delivery quality. This is not a Windows
GPU test. Native menu-to-game route verification is documented separately in
`MENU_STARTUP_VERIFICATION.md`.
Imported external avatars lacking semantic facial parts keep supported body/eye
behavior and are not guessed into a procedural facial rig. Replacement cosmetic
faces without movable semantic lips remain static while their hidden legacy
mouth stays suppressed.
