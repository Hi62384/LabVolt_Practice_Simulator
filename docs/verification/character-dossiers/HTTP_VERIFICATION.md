# Character HTTP integration verification

Verified on Godot 4.5.1 Mono using the production `HostOpenAI` client, real `HTTPRequest` sockets, the production character interaction pipeline, and an isolated loopback provider. The provider returns authored data and delays. This establishes transport, scheduling, validation, and accounting behavior; it does not establish live model dialogue quality, actual OpenAI token consumption, or internet response latency.

The complete five-script suite was rerun against the final character core at checkpoint `d55cd873`, after the context, personal-life consistency, silent-delivery, and native-integration fixes. The refreshed trace contains 85 actual loopback requests across the five scripts. All scripts passed; no further implementation change was needed for this rerun.

## Executed suite

All five scripts passed with isolated user data and no real OpenAI credential:

| Script | Result |
| --- | --- |
| `test_host_openai_client.gd` | Passed existing connection, legacy chat, model discovery, setup, persistence, and usage regressions. |
| `test_teacher_ai.gd` | Passed existing teaching context, input moderation, typed response, microphone WAV/transcription, and model-change regressions. |
| `test_openai_evaluation.gd` | Passed existing comparison budget, cancellation/resume, measured usage, and persisted result checks. |
| `test_character_http_transport.gd` | Passed 59 assertions covering the coordinated response, host validation/repair, assessment boundary, envelope privacy, actual usage accounting, complete context reduction, and invalid/incomplete/long output handling. |
| `test_character_background_http.gd` | Passed 45 assertions covering independent background scheduling, duplicate suppression, cancellation, stale request isolation, actual usage accounting, and credential/model changes. |

The existing Linux CEF extension warning is present. No new script, parse, or compilation errors occurred. Exact request bodies, individual logs, and the pass summary are stored in `http/`. The request trace contains authored test context and no authorization headers or credentials.

## Conversation architecture exercised over HTTP

An ordinary classroom conversation sent one structured text request containing both interpretation and proposed dialogue. The host applied the incident once, checked the proposed delivery against its final emotion and knowledge decision, and moderated the accepted spoken output. Both input and output moderation remained active.

| Turn | Text requests | Moderation requests | Total measured requests |
| --- | ---: | ---: | ---: |
| Ordinary coordinated turn | 1 | 2 | 3 |
| Draft with deliberately inconsistent emotional delivery | 2 | 2 | 4 |
| Assessment request requiring a protected interpretation boundary | 2 | 2 | 4 |

The previous implementation used a separate interpretation request before ordinary speech generation, as recorded by its earlier HTTP regression. The ordinary path now removes that sequential language-model request. The fixture does not justify a numerical claim about live cost savings or response-time improvement.

The deliberately inconsistent draft triggered one repair containing the already resolved host emotion and behavioral decision. Repair did not reapply the incident. Duplicate delivery did not create another relationship consequence or conversation record. A valid interpretation followed by repeatedly invalid delivery stopped after one repair, with an empty spoken response and an explicit technical outcome. Malformed joint interpretation stopped without generating a speculative answer from unvalidated meaning.

Assessment testing supplied a copied problem and private host answer, teaching, display, and instrument markers. Only the interpretation request received the copied problem. The speech-generation request received the bounded assessment intention; neither stage received the private host answer or removed teaching/instrument context. The assessment response passed the host output restrictions and retained both moderation calls.

Other verified invariants include separation of untrusted dialogue from stable instructions; disabled provider storage; configured reasoning effort; complete rather than clipped large dialogue and visual plans; refusal of incomplete token-limited responses, truncated HTTP JSON, malformed structured output, and excessive output; local rejection of irreducible oversized context; preservation of authoritative identity, mood, beliefs, personal history, and the latest coherent turns when lower-priority context is removed.

## Background generation scheduling

One background generation request deliberately remained pending for 1,200 ms. A foreground HTTP response completed in **32 ms** while the background request was still active. The background measurement was **1,228 ms**. These are observed loopback timings for authored delays, not representative model generation times.

A second population request was rejected before sending HTTP or recording usage. Explicit cancellation resolved the waiting coroutine, advanced the generation epoch, and freed the lane. A new generation began immediately. When the old delayed provider response arrived, it could not clear the replacement's busy state or replace its output. Foreground requests remained available during that replacement.

Changing the selected model and disconnecting credentials also resolved pending callers. A current background authentication rejection invalidated the current connection's verification. A delayed rejection for an old credential could not clear verification established with the replacement credential.

The test exercised seven actual background requests: two successful completions, three cancellations, and two authored authentication failures. All seven were counted exactly once. The rejected duplicate was absent from the server trace. Internal population work is recorded as a production feature; the earlier nonempty-draft test classification was corrected.

## Token and latency accounting

The routine fixture response reported input **101**, output **37**, cached input **64**, and reasoning **8** tokens. The interaction trace retained those exact provider fields. Moderation responses without usage retained unknown usage rather than invented counts. The turn recorded three actual requests and **102 ms** total elapsed time in the final run.

The two successful background fixture responses each reported input **611**, output **231**, cached input **128**, and reasoning **17** tokens. Their persisted aggregate was input **1,222**, output **462**, cached input **256**, and reasoning **34**. Cancellation and authentication failures without usage did not add estimated tokens. Reloading the client preserved the measured counts and usage.

These values intentionally test accounting with known HTTP response fields. They are not measured tokenization or model inference consumption. No live generation-quality, naturalness, TTS latency, model cost comparison, or average real gameplay token target is established by this suite.

## Reproduction

Run `python3 tests/campus/ai/run_character_http_tests.py --godot /path/to/godot-mono --output /path/to/evidence` with the matching `DOTNET_ROOT`. The harness starts the threaded loopback provider, isolates each test's user data, removes inherited live-API credentials, checks process exits and script errors, and saves the request trace. `--only-character` runs the two character-specific scripts.
