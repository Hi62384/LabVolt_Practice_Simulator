# NPC Realtime overhaul verification

This is an executable verification procedure, not a claim that physical microphone, live provider or audible listening tests passed. Never commit credentials or personal voice recordings.

## Native regressions

Use the branch's **NPC native regressions** workflow, which installs Windows Godot Mono, builds the project, imports resources, runs the targeted NPC/UI/streaming tests, exercises local WebSocket and HTTP protocol fixtures, then runs the broader NPC regressions. Inspect the logs for the exact commit being tested; a workflow for an earlier commit does not validate a later one. The branch workflow does not publish a game release.

## Capture and provider checks

From the repository root, using an installed Godot 4.5.1 Mono executable and a built/imported project:

```powershell
python tests/campus/academics/run_voice_acceptance.py --godot "C:\path\to\Godot_v4.5.1-stable_mono_win64_console.exe" --source microphone --seconds 6 --capture-only
python tests/campus/academics/run_voice_acceptance.py --godot "C:\path\to\Godot_v4.5.1-stable_mono_win64_console.exe" --source microphone --seconds 6 --live --stt-only
python tests/campus/academics/run_voice_acceptance.py --godot "C:\path\to\Godot_v4.5.1-stable_mono_win64_console.exe" --source microphone --seconds 6 --turns 2 --teacher mr_bro --tts-model gpt-realtime-2.1-mini --live
```

For live commands only, supply a usable OPENAI_API_KEY in the process environment by your usual secure local mechanism. The live checks consume API credit. Do not put the key in a command, repository file, or log. Use the same device and recording conditions across comparisons. For microphone source, do not use headless mode.

## Gameplay acceptance (real device and speakers/headphones)

- Verify the V meter tracks silence, quiet and loud speech, and falls after release. Open inspector and proximity conversations with a teacher and a seated student. Confirm only the actual target reports Listening/Hearing, Transcribing and the real recognized transcript. In multiplayer, verify other peers do not receive private transcript labels.
- Compare the same short and multi-sentence dialogue on Realtime Mini and the previous configured speech model. Record cold connection and warm reused connection independently. Interrupt speech; no stale audio should resume. Walk out of range, switch rooms, disable speech, and repeat a turn. Check text remains visible in the inspector and the character can continue a detached conversation.
- Put a nearby student and distant teacher in simultaneous speech; switch relative loudness and walk behind walls/floors. Captions should follow the more audible character, avoid inspector and HUD, and stay absent for inaudible sources. With speech disabled verify near text-only fallback. Check mouth motion against audio, especially at packet boundaries.
- Audition each faculty member's normal, sad and angry variants with the same sentence. Approve only if the identity remains consistent and the moods sound distinct. Repeat after save/load. Include a same-base preset edit and verify it does not change the active voice before approval.
- Compare Chad's reactions to business, status, dependence, independence and whether to drop out for Hustlers University. Compare the same casual statement and repeated question across all faculty and a diverse student sample. Check personality, beliefs and natural silence/acknowledgment without canned trigger responses. Academic questions must still be accurate; graded assessment privacy and gameplay authority must be preserved.

## Evidence and comparisons

For before/after comparisons use separate worktrees on the pre-overhaul baseline and the exact candidate commit. Match text model, effort, STT model, user input, spoken text, voice mode, account and network conditions. Record warm and cold cases separately; do not compare a cached playback against an uncached generation. Use multiple runs and report sample count, median and worst observed latency.

Capture NPC and voice diagnostics for text first token, text completion, queue time, speech first PCM, first audio submission, response completion, packet gaps, generator skips, connection reuse and provider-reported usage. Actual speaker audibility, emotional quality and lip sync require listening; generator submission is not physical speaker onset. The received-audio rate is a delivery estimate, not provider compute throughput. Unreported token values must stay unknown, not zero. Local cost estimates are not invoices.

| Measurement | Baseline | Candidate |
| --- | --- | --- |
| Cold / warm first audible speech | Not measured | Not measured |
| Continuous rendition interruptions | Not measured | Not measured |
| Per-turn text / STT / speech provider usage | Not measured | Not measured |
| Actual charged cost | Not measured | Not measured |
| Physical microphone and acoustic quality | Not verified | Not verified |
