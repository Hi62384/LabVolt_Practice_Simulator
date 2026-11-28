# Microphone and graceful departure verification

These runs verify the production audio-routing and persistence code with controlled inputs on Linux using Godot 4.5.1 Mono. They do **not** establish physical microphone operation, Windows compatibility, live OpenAI behavior, audible speech quality, or custom-voice quality. The Windows tunnel was unavailable during this work.

## Results

| Test | Result | What the test observes |
| --- | --- | --- |
| `test_microphone_capture_lifecycle.gd` | PASS | A generated tone travels through the actual AudioServer capture effect and C# processing. The capture bus preserves amplitude while a separate monitor bus is muted. Independent consumers retain the same device and recording state; sensitivity changes do not restart it. A 1.98-second pause remains in the turn, two seconds ends it, and a short onset produces a final discard. |
| `run_natural_voice_gameplay.py` | PASS, 22 checks, 0 failures | The real Main scene starts through its normal menu. Injected PCM reaches host-observed NPC targeting, the production HTTP transcription/reasoning adapters, character memory and positional speech playback using a local fixture provider. Follow-ups, target changes, actual PTT key events, manual recording with the interaction UI open, chat interruption, mute and range gating are exercised. |
| `test_session_graceful_lifecycle.gd` | PASS | Offline exits remain immediate. Repeated deliberate exits share a single drain and a single leaving notification. A delayed exit continuation cannot close a replacement connection. |
| `run_student_population_departure.py` | PASS, four scenarios | Separate host and client processes use the real Session and ENet protocol. Host departure, client departure, both worlds paused, and a deliberately missing receipt are covered. A new memory object reopens the recipient's saved file to confirm the final same-frame event. |

The recorded host departure acknowledgment took **57 ms**. With both worlds paused it took **50 ms**. The deliberately unresponsive recipient timed out after **2012 ms**, within the two-second polling limit plus one frame, and the host retained its local event. These are fixture timings, not network performance guarantees.

## Failure reproduced and corrected

Before the departure change, creating a social event, calling the synchronous local flush and closing ENet in the same frame left the event on the host only. The client's saved memory contained the earlier event but not the last one.

Deliberate leave and quit now run the existing leaving callbacks, then use a reliable ordered checkpoint on the same channel as population updates. The recipient saves memory, population changes and the social archive before returning a receipt tied to a random nonce and the expected player identity. The connection closes after receipts arrive or the bounded wait expires. Connection failures and replacement APIs retain synchronous cleanup. A timeout reports that delivery was not confirmed; it does not claim remote persistence.

Immediate disconnect handling also clears pending fetches and sent-profile caches. Replacing the transport resets those caches even when the local owner and server/client role are unchanged, so a reused peer number does not inherit another connection's assumed profile state.

## Evidence and limits

`results.json` records the scope and outcomes. The adjacent logs contain the capture, actual-Main and Session lifecycle runs. `departure/` contains eight raw host/client process logs for the four departure scenarios. Each Linux Godot process reports the repository's three expected Windows-only CEF loading messages. These runs contain no unexpected engine or script errors.

All audio inputs and provider responses in these tests are synthetic. Saved user-data directories, credentials, recordings and real participant data are excluded. A physical microphone, operating-system permissions, acoustic echo behavior, live OpenAI services and Windows still require testing in the corresponding environment. A broken connection or terminated process cannot guarantee that another device received its most recent update; already saved host records remain the recovery source.

## Reproduction

Use the Mono engine and its compatible .NET runtime. Give standalone Godot tests fresh `XDG_DATA_HOME` and `APPDATA` directories and remove `OPENAI_API_KEY` from their environment. The Python runners create isolated user-data directories and use local fixtures.

```sh
godot --headless --path . --script res://tests/campus/academics/test_microphone_capture_lifecycle.gd
python3 tests/campus/academics/run_natural_voice_gameplay.py --godot /path/to/Godot_mono
godot --headless --path . --script res://tests/campus/academics/test_session_graceful_lifecycle.gd
python3 tests/campus/academics/run_student_population_departure.py --godot /path/to/Godot_mono
```
