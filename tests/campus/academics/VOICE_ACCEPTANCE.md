# Microphone, transcription and NPC voice acceptance

Use `run_voice_acceptance.py` with a built Godot Mono project. The runner creates
isolated user data outside the source repository, saves `result.json` and
`engine.log`, and treats script errors as failures. It never accepts an API key
as a command-line argument. Set `OPENAI_API_KEY` in the local process environment
for live tests; `--live` explicitly enables billable provider requests.

## What each result establishes

| Result | Verified path | Still requires a person/device |
| --- | --- | --- |
| `load_only_pass` | Real Main scene and production scripts load | All audio, provider and gameplay behavior |
| `capture_pass`, source `fixtures` | Included spoken WAV → actual AudioServer capture bus → native PCM resampler; independent repeated capture | Physical microphone and permissions; provider recognition; audible output |
| `capture_pass`, source `microphone` | Real AudioStreamMicrophone capture with sample count, duration, peak and RMS | Recognition and NPC response; human listening |
| `stt_pass` | Captured input → actual selected provider → exact normalized known phrase | NPC reasoning, memory and synthesized playback |
| `pipeline_pass` | Capture → actual STT → production NPC queue/memory → non-silent synthesized PCM → engine playback and captions; second-turn nickname recall | Human-audible quality, character/teaching quality, multiplayer and exported Windows behavior |
| `fixture_pipeline_pass` | The same capture, NPC, memory, synthesis-adapter and playback code with authored loopback provider responses; three distinct input recordings and nickname continuity in the actual request context | All live-provider recognition, reasoning and voice quality; physical microphone and audible output |
| `unavailable`, exit 2 | A required device/credential was unavailable | This is not a functional pass |

The harness never automatically claims human-audible output. Read the captions
and listen for voice identity, expression, naturalness, technical accuracy and
interruptions before accepting those qualities. Raw microphone recordings are
not written. The report keeps transcript/reply hashes rather than their text;
known test phrases, device names, timing and usage evidence are recorded.

## Example commands

Replace `GODOT_MONO` with your local Godot Mono executable. Run from this
repository with Python available. Choose an output directory outside the repo.

```sh
# No microphone or API access; validates Main/script loading.
python tests/campus/academics/run_voice_acceptance.py --godot GODOT_MONO \
  --headless --load-only --output /tmp/labvolt-voice-load

# Included intelligible spoken fixtures, actual capture bus, no provider calls.
python tests/campus/academics/run_voice_acceptance.py --godot GODOT_MONO \
  --headless --capture-only --turns 3 --output /tmp/labvolt-voice-capture

# Repeatable full NPC path with authored local providers, no credentials.
python tests/campus/academics/run_recorded_voice_pipeline.py --godot GODOT_MONO \
  --output /tmp/labvolt-recorded-npc-pipeline

# Use a real microphone. A native game window displays the exact phrase.
python tests/campus/academics/run_voice_acceptance.py --godot GODOT_MONO \
  --source microphone --capture-only --device Default --seconds 6 \
  --output /tmp/labvolt-microphone

# Actual STT with repeatable included phrases and your configured key.
python tests/campus/academics/run_voice_acceptance.py --godot GODOT_MONO \
  --headless --live --stt-only --turns 3 --stt-model gpt-transcribe \
  --output /tmp/labvolt-live-transcription

# Real providers and actual NPC routing, memory, synthesis and engine playback.
python tests/campus/academics/run_voice_acceptance.py --godot GODOT_MONO \
  --live --turns 3 --teacher mr_bro --output /tmp/labvolt-npc-voice

# Real microphone and complete NPC pipeline. Use headphones; speak on cue.
python tests/campus/academics/run_voice_acceptance.py --godot GODOT_MONO \
  --source microphone --live --turns 3 --seconds 6 --teacher dr_volts \
  --output /tmp/labvolt-npc-microphone
```

Windows accepts the same options with native paths, e.g. `--output
C:\Temp\LabVoltVoiceCheck`; run each command on one line or use PowerShell's
continuation syntax. `--text-model`, `--stt-model`, and `--tts-model` preserve
explicit test selections. Defaults are the production host-client defaults.
Custom voice assignment comes from the selected character's production profile.
This harness uses a separate profile and does not alter your gameplay saves.

The normal prerecorded path replaces only the microphone player's stream. It does not
inject a transcript, call the dialogue generator directly, or replace provider
responses. Source audio traverses the actual capture bus before the same PTT
turn and NPC path used in gameplay. The included WAVs contain original phrases
synthesized with CMU Flite's `slt` voice, with hashes in `voice_fixtures/manifest.json`.
`voice_fixtures/generate.py` regenerates them with FFmpeg; this is a test-only tool.

The separate `run_recorded_voice_pipeline.py` runner uses those same recordings
and authored loopback STT/text/voice responses. It verifies exactly one
transcription request per turn, checks that the first nickname actually reaches
the second turn's production conversation context, and checks resource cleanup.
Its report identifies `loopback_fixture`, sets `provider_requests` to false,
and cannot produce a live-provider pass. The fixture port override is restricted
to editor builds and is mutually exclusive with `--live`.

`run_microphone_render.py --godot GODOT_MONO --output OUTPUT` checks the actual
settings page at 1280×720 and 960×540, saves rendered PNGs and geometry evidence,
and checks local sample status and controls. It uses the current native display;
in a Linux environment with the project's Xorg dummy-display setup, add
`--xorg-display 87` to start a separate software-rendered display. This is UI
verification, not a microphone or audible-output test.

For multiplayer microphone ownership and ENet routing, use the existing
`test_classroom_live_microphone.gd` host/guest harness. That harness explicitly
uses fixture provider responses and does not establish real provider quality.
For actual multiplayer acceptance, repeat the native game interaction with two
machines, separate microphones and the configured host provider. Record guest
input, host usage, correct target, guest playback and cancellation evidence.

## Regression and local performance checks

`test_microphone_turn_reliability.gd` covers quiet explicit PTT, pauses longer
than automatic VAD's timeout, silence rejection, cancellation, worker PCM and
per-peer duplicate-turn protection. `test_microphone_local_sample.gd` covers the
settings sample recorder/replay, low-level audio, selected-sample cloud submission
and canceled-test stale results. `test_streaming_transcription.gd` covers
transcription event ordering, early failures, cancellation and error categories.

`benchmark_transcription_audio.gd` compares the frozen pre-change resampler and
WAV packing against current production entry points for 1, 10, 30 and 180 second
buffers. It records five timings per operation and separately measures worker
submission and completion. These are local preprocessing measurements; they say
nothing about live-provider latency, voice quality or network cost.

## Provider contracts checked

The transport follows the current OpenAI [transcription guide](https://developers.openai.com/api/docs/guides/transcription),
[Realtime transcription guide](https://developers.openai.com/api/docs/guides/realtime-transcription),
[client events](https://developers.openai.com/api/reference/resources/realtime/client-events),
and [server events](https://developers.openai.com/api/reference/resources/realtime/server-events).
The file workflow handles completed recordings. Dedicated streaming choices use
`session.update` with transcription configuration, 24 kHz mono PCM, explicit
append/commit, and final-item correlation. The existing workflow opens a bounded
session for a completed recording; it does not claim simultaneous live microphone
upload. A failed item can arrive before commit acknowledgement, and must be
retained until its item identity is known. Cancellation must prevent late events
from publishing a transcript.
