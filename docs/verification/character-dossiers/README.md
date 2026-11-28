# Character identity implementation and acceptance evidence

Baseline: `7ec6c95241fca70e724783d6234dc3f445a6630c` on `windows-launcher`.
Development branch: `dev/character-dossiers-20261127`.

This change replaces ordinary response selection with persistent character
dossiers, relevant-context retrieval and a coordinated character interaction
pipeline. The host retains authority over observations, equipment, grades,
physical actions, relationships and persistence. The configured AI develops
fictional people and proposes their words and intentions.

**Implementation and local integration have been exercised; live model quality
has not been certified.** This environment had no configured OpenAI credential.
Authored provider fixtures establish transport and validation behavior, not
natural dialogue, generated-student diversity or actual model token cost.
The live acceptance harness reports a skip when credentials are unavailable.

## How the systems fit together

The existing profile API now returns a lightweight projection of the same
authoritative dossier used by conversations, student simulation, classroom
teaching, appearance, voice and the E inspector. There is no separate generic
voice-assistant persona. Existing mood, belief, relationship, verified-learning,
movement, speech queue, academic and network systems remain in place.

The store contains full identity and appearance; interconnected life sections;
written personality and speaking descriptions; values, interests, goals and
beliefs; independent numerical traits; knowledge and ignorance; representative
dialogue examples across moods; and permanent vocal characteristics. The
existing Brain owns developing personal records and actual game experiences.
They are accessed through one character identity without duplicating mutable
history in two authorities. See [dossier architecture](DOSSIER_ARCHITECTURE.md)
for fields, limits, migration rules and every existing teacher's specification.

### Generation and population

Generation normally uses one coordinated request for a complete person. The
prompt requests 700–1,100 words across 6–12 life sections, extensive personality
and speaking descriptions, all 107 numerical traits, and at least 34 varied
examples spanning 17 moods and at least 20 situations. The host validates the
whole dossier before making the person available.

The background lane permits one in-flight generation job. It aims for a reserve
of 12 ready students while preserving the classroom's zero-to-six additional
NPC capacity. At most four new-student jobs are queued together. Existing ready
characters can attend immediately; a class never awaits sequential dossier
requests. Generation retries are bounded to three attempts, preserve completed
sections, and repair invalid sections rather than regenerating everything.

Jobs and partial drafts persist. A host/model/session change invalidates stale
work. Publication checks personal canon again, including facts established by
a foreground conversation while background generation was pending. A stale
draft is held and repaired against current canon. A generation request that
cannot fit all required canonical constraints within its transport ceiling
is explicitly held rather than silently dropping established information.

Existing saved people migrate with their names, appearance, voice, histories,
academic progress, relationships and social decisions intact. Existing authored
teacher seeds stay available while expansion runs. A new offline host with no
saved students has an empty ready reserve; it does not manufacture template
students and mislabel them as complete AI-generated people. Generation status
is visible in inspection diagnostics.

### Conversation, memory and consistency

Ordinary typed and transcribed input enters the same pipeline:

1. Retrieve core identity, current mood, the relevant relationship, selected life
   sections, a few suitable style examples, relevant established personal facts
   and recent conversational context.
2. Moderate the incoming message. One structured model response normally
   supplies interpretation, proposed behavior, speech, delivery and memory
   changes together.
3. Apply the perceived incident once using host-owned state. Validate the draft
   against the resulting emotional/behavioral decision, individual knowledge,
   assessment restrictions, established life facts and supported actions.
4. Moderate accepted spoken output. A bounded repair can correct an inconsistent
   draft. Consequential or ambiguous claims receive a separate semantic check
   when local validation cannot decide them reliably.
5. Deliver words and supported nonverbal behavior separately. Persist new
   fictional facts and decisions only through the validated delivery path.

Assessment interactions retain a separate interpretation boundary so copied
problems and private answers do not enter ordinary character speech generation.
Official safety instructions remain deterministic and do not wait for AI.

The expandable life ledger records natural details, canonical values, topics,
aliases, entities, links, chronology, provenance and revisions. Historical
facts, changing preferences, current records and opinions have distinct update
semantics. An explained new record or correction preserves the previous value.
Quotes reported by players remain reports; they do not become host-observed
events or verified grades.

Validation examines the actual spoken line as well as proposed memory changes.
Regression cases include a conflicting number without a memory proposal, a
canonical value absent from its quoted detail, negation, a correct number for
one lift masking a wrong number for another, written-out quantities, fictional
prose contradicting existing life history, and invented prior player behavior.
See [life consistency verification](LIFE_CONSISTENCY_VERIFICATION.md).

The host rejects a response if its selected character, class phase, host
namespace or dossier revision changes while it is pending. Explicit completion
receipts make an empty final response idempotent: a retry cannot attach new
words or personal facts to an already completed silent turn. A listening-only
event can still be completed once by its subsequent delivered response.

### Genuine social boundaries and local behavior

Personality values affect attention, effort, work, social initiative, conflict,
emotion recovery, movement and gestures locally. They are not merely displayed
in an inspector. Low teaching motivation does not automatically make an
energetic, sociable character withdraw from casual conversation. Permanent
disengagement uses the actual canonical `grudges` trait, with a serious
host-observed conflict requirement.

Permanent silence is specific to a relationship and persists across time,
apologies, topic changes and restarts. Necessary safety or official communication
can happen without clearing that decision. Reconsideration requires meaningful
new verified experiences, sufficient disposition to forgive, an explicit new
character decision, and validated delivery; eligibility never forces forgiveness.
A repeated old delivery cannot erase a newer boundary.

Intentional silence has an empty spoken line. Ordinary offline failures also
produce no invented character line and carry a separate technical status.
Supported gestures can occur without speech. Narration is only permitted for
behavior actually performed. The old ordinary response tables, exact-question
personal answers and generic apology/refusal replies are removed from delivery.

Classroom greetings, attendance reminders, wrap-ups, call-ons, social exchanges
and group contributions pass underlying intentions and released facts to the
character. The host still controls curriculum coverage, assessment timing,
answer privacy and grading. Offline group work does not insert canned NPC notes.

## Inspector and voice

Pressing E on a nearby NPC opens six organized sections: Overview, Personality,
Life history, Relationships and reputation, Emotions, and Developer diagnostics.
Text, microphone and relevant classroom controls remain available. Data updates
without treating inspection as a social encounter or triggering AI generation.

Remote snapshots require the authenticated selected character, matching class
and range. Stale requests cannot act on a replacement teacher. Other players'
private conversations and host diagnostic material are not sent to ordinary
clients. The host/developer diagnostic view shows real retrieved context,
selected examples, interpretation, intention, memory/persistence outcome,
provider usage, request count and available timings. See
[inspector verification](INSPECTOR_VERIFICATION.md).

Permanent voice identifiers remain stable. Current emotion, intensity, speaking
manner and intention affect delivery instructions, rather than selecting a new
voice. Host-side timings distinguish queueing, transcription, character
processing, text readiness, synthesized-audio readiness and actual local
playback start. Unknown remote playback or microphone-device latency is not
displayed as zero or inferred from host timing.

## Rendered facial repairs

Eyes have matching explicitly tagged hierarchies and authored rest transforms.
Blink and expression use separate pivots. Anchored eyebrow geometry retains
length, glasses are identified semantically, and a single compositor coordinates
expression, resting lips/teeth and the speech aperture. Ending speech restores
the current mood rather than revealing an old grin.

Actual Main-scene inspection found an additional defect: procedural character
meshes lacked UV attributes, causing black face, hair and clothing surfaces
under the campus anisotropic texture setting. Complete UVs correct this path
without changing lighting or graphics quality. The speech aperture has UVs too.

The [facial verification report](FACIAL_VERIFICATION.md) contains baseline and
updated native renders, the final 4,878-assertion geometry/ownership suite, 18
actual Main-scene captures across two faculty models, and the existing 14-extreme
body-deformation regression. The rendered captures include neutral, happy,
angry, sad, tired, excited, angry blink, sad speech and the expression after
speech ends. Playback used an audio fixture, so this is rendering evidence,
not live TTS quality evidence.

## Measured efficiency and its limits

| Measurement | Baseline | Updated | Interpretation |
| --- | ---: | ---: | --- |
| Interpretation/dialogue requests for an ordinary valid turn | 2 | 1 | Observed production invocation order with an identical deterministic provider fixture. |
| Input/output moderation calls for that turn | 2 | 2 | Required moderation remains. |
| Serialized context for that comparison | 9,218 + 10,550 bytes | 6,827 bytes | Context payload only; not tokens, complete prompt size, or a live cost estimate. |
| Teacher profile lookup | 61.570 µs | 36.028 µs | Full caller path, 500 calls per case, same benchmark environment. |
| Student profile lookup | 65.768 µs | 25.342 µs | Full caller path; updated case uses a complete synthetic dossier. |
| Full-dossier retrieval | No equivalent baseline operation | 3.030 ms mean | 100 local retrievals of the validated fixture. |

See [request accounting](REQUEST_ACCOUNTING.md) for exact invocation logs and
[dossier architecture](DOSSIER_ARCHITECTURE.md) for storage and lookup evidence.
The ordinary local pipeline probe took 1.483 ms before and 3.139 ms after: the
extra consistency work has a small measurable local cost, and no live response
speedup is inferred from removing a request.

The [HTTP integration suite](HTTP_VERIFICATION.md) used real production HTTP
sockets with an authored loopback provider. A foreground response completed in
32 ms while background generation remained delayed for roughly 1.2 seconds,
establishing independent scheduling. Provider-supplied input/output/cache/
reasoning usage is preserved exactly, and missing usage remains unknown. Those
fixture quantities are accounting tests, not actual OpenAI token consumption.

The 1,000–3,000-input-token target, actual model generation duration, average
live response latency, microphone-to-audio latency and multiplayer inference
throughput remain unmeasured. The code records real values when the configured
provider supplies them; this report does not substitute character counts or
fixture timings for those measurements.

## Reproduction and outstanding verification

The [final regression report](REGRESSION_VERIFICATION.md) and
[consolidated regression manifest](regressions/summary.json) record **58
passing suites**: all 45 default character regressions plus 13 additional
classroom/teacher gates. Affected tests were retaken after integration fixes;
the manifest identifies the selected successful run for each case. The
[source manifest](regressions/source-manifest.json) verifies that all 684
production GDScript, C# and shader file hashes remained unchanged through
the final frozen verification interval.

| Final verification area | Result and evidence |
| --- | --- |
| Core and classroom regressions | 58/58 suites pass; full logs in `regressions/`. |
| Production HTTP client | All five suites pass, including 59 transport and 45 background assertions; [HTTP report](HTTP_VERIFICATION.md). |
| Complete character restart | Actual Main writer/read processes pass 45/93 checks; [restart report](RESTART_NETWORK_VERIFICATION.md). |
| Separate multiplayer peers | Facing, classmate, phone and human-discipline host/client scenarios pass; same report. |
| Generation publication | Schema, scoped repair, corruption, host isolation and concurrent canon checks pass; [dossier report](DOSSIER_ARCHITECTURE.md). |
| Native rendering | 4,878 geometry/ownership assertions and 18 actual campus facial captures; [facial report](FACIAL_VERIFICATION.md). |
| E inspector | Native layouts at 1280 × 720 and 800 × 600, real controls, selected-player privacy and ENet request guards; [inspector report](INSPECTOR_VERIFICATION.md). |
| Mandatory startup | Singleplayer and Host Game Play pass headless and native, using the production relay; [startup report](MENU_STARTUP_VERIFICATION.md). |
| Live configured AI | Skipped because no credential was available; model naturalness, real usage averages and live TTS remain unverified. |

Use the repository's Godot 4.5.1 Mono build and .NET runtime, with disposable
user data. The core harness now includes 45 default scripts; HTTP, full-dossier
generation, process restart, native rendering and external-peer tests have
their own harnesses. The [menu startup report](MENU_STARTUP_VERIFICATION.md)
documents both required Singleplayer and Host Game Play routes, including
pointer-driven native execution with the production relay implementation.

```sh
python3 tests/campus/academics/run_character_regressions.py --godot /path/to/godot-mono --dotnet-root /path/to/dotnet --output /path/to/results
python3 tests/campus/academics/run_character_process_restart.py --godot /path/to/godot-mono --dotnet-root /path/to/dotnet --output /path/to/restart
python3 tests/campus/academics/run_character_network_checks.py --godot /path/to/godot-mono --dotnet-root /path/to/dotnet --output /path/to/network
python3 tests/campus/ai/run_character_http_tests.py --godot /path/to/godot-mono --output /path/to/http
```

Run the separate dossier commands documented in
[DOSSIER_ARCHITECTURE.md](DOSSIER_ARCHITECTURE.md). For configured live AI, use
the core harness's explicit `--include-live` option with `OPENAI_API_KEY` set in
the environment. Its transcript and actual usage must be reviewed before
declaring the model's characters natural, diverse and consistent across all
requested scenarios. No credential belongs in a committed fixture or report.

The [restart and network report](RESTART_NETWORK_VERIFICATION.md) records two actual
Main processes (45 writer checks and 93 reader checks), four passing ENet
host/client scenarios, and 18 group scheduling/cancellation checks. The native
[2,001-record ledger probe](local-memory/ledger-2001-records.log) measured
0.33985 ms per indexed lookup over 100 queries, used 426,810 serialized bytes,
and made no provider request. The [compiler result](build-summary.json) records
a clean C# build with zero warnings and errors.

The Linux environment cannot load the repository's Windows-only CEF extension.
Its three baseline extension errors are distinguished from script/compilation
errors. Native rendering here used Mesa llvmpipe; Windows GPU behavior and
hardware gameplay frame rate were not tested. General language consistency is
not mathematically guaranteed by local keyword/concept retrieval and structural
validation. Live transcript review remains a real acceptance requirement.
