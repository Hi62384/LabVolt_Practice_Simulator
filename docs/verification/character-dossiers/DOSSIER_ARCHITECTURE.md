# Persistent character dossier architecture and verification

## Implemented behavior and evidence boundary

Characters now have one host-owned dossier containing stable identity, appearance, life-history sections, a written personality, a written speaking description, representative dialogue examples, numerical traits, knowledge boundaries, and permanent vocal identity. Ordinary gameplay reads a lightweight projection of that authority. A bounded background generator expands existing people and creates new adult students through the configured AI client. A character enters the ready population only after whole-dossier validation and durable storage.

Existing authored teachers and previously saved students remain available while expansion is pending. They are explicitly labeled `needs_expansion` / `legacy_migration`; their short inherited biographies are not presented as completed AI-generated dossiers. A fresh host with no saved students and no available AI has an empty ready reserve and can still begin a class immediately. The system does not fill those seats with newly generated template people. The established zero-to-six additional-student classroom capacity is preserved.

**No live AI credential was available in this verification environment.** The actual live acceptance script parsed and reported `SKIP` with exit code 2. Complete dossier fixtures below verify schema, generation orchestration, persistence, retrieval, and gameplay integration. They do not prove the naturalness, diversity, biography coherence, or spoken delivery of an actual model. Those acceptance checks remain runnable through the configured model.

## Authority and retained systems

| Component | Responsibility |
| --- | --- |
| [character_dossier.gd](../../../scripts/campus/academics/character_dossier.gd) | Dossier schema, historical migration, publication validation, lightweight projection, section/example retrieval, and complete-sentence selection. |
| [character_dossier_store.gd](../../../scripts/campus/academics/character_dossier_store.gd) | Host namespace, persistent dossiers and jobs, atomic saves, valid backup recovery, corruption protection, immutable identity checks, and per-character projection cache. |
| [character_dossier_generation.gd](../../../scripts/campus/academics/character_dossier_generation.gd) | Coordinated background generation, bounded retries, partial repair, cancellation, reserve expansion, and custom-teacher publication. |
| [class_character_profile.gd](../../../scripts/campus/academics/class_character_profile.gd) | Existing gameplay API backed by the authoritative store; teacher seeds, classroom numeric projection, permanent voice selection, and mood-first vocal delivery. |
| [character_personas.gd](../../../scripts/campus/academics/character_personas.gd), [character_traits.gd](../../../scripts/campus/academics/character_traits.gd), [character_worldview.gd](../../../scripts/campus/academics/character_worldview.gd) | Canonical teacher specifications, authored numerical constraints, and historical migration inputs. Existing sample lines remain historical reference data and are not selected as ordinary replies. |
| [student_population.gd](../../../scripts/campus/academics/student_population.gd), [faculty_roster.gd](../../../scripts/campus/academics/faculty_roster.gd) | Persistent resident membership, stable identifiers, reserve demand, existing-location exclusion, and validated teacher registration. |
| [character_life_memory.gd](../../../scripts/campus/academics/character_life_memory.gd), [character_memory.gd](../../../scripts/campus/academics/character_memory.gd) | Developing personal facts with provenance and revisions; existing observed gameplay, conversational, relationship, learning, and emotion persistence. Large immutable life sections are not copied into the developing fact ledger. |
| [character_interaction.gd](../../../scripts/campus/academics/character_interaction.gd) | Shared typed, microphone, teacher, and classmate interaction pipeline: retrieval, interpretation, host appraisal, validated speech and proposed changes, and commit only after actual delivery. |
| [host_openai_client.gd](../../../scripts/campus/ai/host_openai_client.gd) | Existing configured provider, moderation, actual usage/latency accounting, and a separate cancellable background HTTP lane. |

Existing assessment integrity, grading, equipment authority, learning outcomes, class capacity, supported actions, speech queue, local movement, emotions, relationship history, and networking remain game-owned. Generation cannot modify them by writing a biography. The E inspector reads the same authority without initiating an AI request; see [inspector verification](INSPECTOR_VERIFICATION.md).

## Stored dossier and validation

Dossier version 1 uses these principal fields:

| Field | Contents and publication rules |
| --- | --- |
| `identity` | Stable ID, name, adult whole age 18–110, role, student program where applicable, background, physical description, and actual supported Toon appearance. An existing ID, name, age, role, program, appearance, and voice ID cannot change during expansion. |
| `life_history` | Independently retrievable sections with unique IDs, title, prose, topics, entities, optional aliases, chronology, and fictional provenance. Full generation requires at least six substantial sections and at least 3,600 characters of life prose. The generation prompt requests 6–12 interconnected sections totaling 700–1,100 words. |
| `personality` | At least 1,000 characters of connected description plus motivations, values, interests, strengths, weaknesses, habits, and personal beliefs. |
| `communication` | At least 650 characters describing the person's speech, plus at least 34 distinct examples covering all 17 requested mood categories and at least 20 situations. Examples are retrieved as linguistic references, never chosen as ready-made responses. |
| `traits` | All 107 independently supplied numerical dimensions, each within 0–1, including teacher-specific constraints where established. |
| `trait_evidence` | Reasons and low/moderate/high bands for 12 important independent dimensions. A contradictory numeric band fails local validation. This is a useful check, not proof of every sentence in the description. |
| `knowledge` | Education, expertise, ignorance, and bounded domain values. Personal biography and opinions use the interaction pipeline's personal-conversation path rather than treating every personal topic as an academic expertise query. |
| `voice` | Permanent supported voice identifier, vocal profile, natural characteristics, and delivery tendencies. Mood affects delivery and pace; it does not regenerate the voice identity. |
| `compact_core` | Distinctive core description, 350–2,400 characters at validation, generated from the complete identity. The prompt normally requests no more than 1,800 characters. |
| `established_biography`, `generation`, `revision` | Preserved historical personal anchors, genuine generation/migration status and measurements, and content revision used to invalidate cached projections. |

One dossier is bounded to 256 KiB. Lists, scalar types, finite numbers, duplicate section identifiers, example coverage, unsupported appearance values, and malformed generation state are checked before publication. Unsupported raw appearance data is rejected for repair rather than silently clamped into a different appearance.

The full biography is stored locally. `Dossier.project()` does not repeatedly duplicate it into every classroom profile or also place all narrative paragraphs in the fact ledger. The full data is fetched for the inspector and selected interaction retrieval. Appearance survives projection and reaches the actual Toon model construction path.

### Persistence and migration

The host namespace stores dossier and generation state at `user://character_memory/<host-identity-hash>.dossiers.json`; population version 2 lives alongside it in `.population.json`. Existing brain memory and learning stores retain their responsibilities. Migration accepts population versions 1 and 2 and preserves previously saved names, bodies, traits, voice, relationships, learning, and personal information.

Older deterministic student identities are reconstructed only where an earlier memory/learning save or actual saved population establishes that they existed. `legacy_student()` is explicitly a migration helper. Fresh population demand never invokes it to invent replacement residents. Test-only `legacy_population_fixture.gd` constructs historical inputs for old gameplay tests; it is absent from production generation.

The previous Mr Bro bench-record seed is retained only for migration of an established older host. Loading a pre-version-8 brain save preserves the old authored teacher biography anchors, including facts that had not yet been explicitly discussed. A fresh teacher profile does not receive the old hardcoded number. Existing saved personal records take precedence, and new fictional details are developed through the interaction pipeline.

Public network snapshots are explicitly scoped as public views. They cannot be projected through a private local dossier, persisted as incomplete identities, or queued for private generation. This also prevents a same-ID resident on a different host from being confused with a client's saved local resident.

Saves use temporary files and valid backups. If both copies are damaged, their bytes are preserved and writes are blocked instead of replacing the resident population. A bounded eight-namespace unsaved cache protects data during host switching. The population supports up to 4,096 residents, while the store allows 4,128 identities and 128 MiB total data. These are resource bounds, not a claim that 4,096 fully expanded people were benchmarked.

## Generation and reserve scheduling

`Generation.configure(client, population, brain)` binds the host, restores completed custom teachers, and queues existing people needing expansion. `tick(preferred_ids)` launches at most one job, at least five seconds after the previous start, and yields immediately to gameplay. It does not start while the foreground client is occupied. An already running background HTTP request has its own lane and therefore does not hold the foreground conversation lock.

The initial reserve demand is 12 students. At most four new student jobs are queued simultaneously; ready residents are reused, and the existing class-location exclusion prevents one identity appearing in incompatible classes. Reserve demand is separate from classroom capacity and does not make a class wait for generation.

A job normally makes one coordinated request with a 10,000-output-token limit. That limit is a request setting, not measured consumption. It requests the full coherent person, including appearance, history, 107 traits, knowledge, voice, and examples together. It does not build a student by randomly combining demographic or biography templates. Existing teacher generation receives its canonical design and immutable constraints.

Validation failures preserve the completed draft and request only invalid top-level sections. Traits and their evidence are repaired together when either disagrees. There are at most three attempts, with bounded retry delays. Job state, partial draft, invalid sections, counts, errors, and available provider measurements are saved. Interrupted running work requeues while retaining completed sections. A validated dossier that could not be saved retries publication; it does not pay for another completed biography. A saved dossier missing from population membership is imported on recovery.

Profile changes, model changes, credential changes, or cancellation invalidate the relevant generation epoch. A late result cannot publish into another host. Request attempts, measured requests, cancellations, and interrupted requests are distinct diagnostics; unknown usage remains unknown. Failed jobs are visible and can be explicitly retried through `retry_failed(id)`.

Custom teacher creation uses `request_teacher(course, design)`, deduplicates equivalent pending work, and returns a queued status. Up to 12 custom or pending instructors are allowed. `Roster.add_generated()` runs only after the complete dossier has passed validation and storage. Reopening the same host restores the saved instructor without another generation request.

### Concurrent personal-history changes

The generator reads the same Brain personal-record ledger used by foreground conversations. Each request receives current canonical values, details, provenance and relevant revision information. Persisted jobs retain semantic content hashes rather than a second mutable copy of the ledger. Timestamp-only repetition of an unchanged fact does not invalidate a draft.

Before publication, the generator captures current canon again. A foreground conversation that established or revised a fact while background HTTP was pending prevents publication of the stale draft. The completed draft is retained for a bounded `life_history` / `compact_core` repair against the latest records. Definite conflicting claims in other narrative fields are also selected. A contradictory personal dialogue example is patched individually: its original ID, situation, mood, relationship and prompt remain, and all unrelated examples and completed traits stay unchanged. Publication recovery after a storage failure applies the same freshness check before publishing or sending another request.

Canonical constraints are compacted without silently discarding facts. If the complete generation/repair request still exceeds the transport's **60,000-character context ceiling**, the job is held with an explicit error and its completed draft preserved. No request is sent or counted. This is a documented resource limit for an unusually large existing personal ledger, not a claim that such a ledger can always be expanded within one request.

The held-request regression also exposed and fixed JSON numeric-representation equality in authored appearances. An unchanged appearance survives a JSON round-trip; an actual body edit remains invalid; publication copies the exact established appearance rather than allowing numeric-representation drift.

## Preserved teacher specifications

All 21 established roster entries have one canonical design specification in `Personas.DESIGN`. Original appearance and courses remain in `faculty_roster.gd`; the existing faculty configuration provides retained classroom defaults. Explicit identity traits override conflicting old derived values, and expansion receives numerical bounds around those anchors. The following is a design/migration audit, not a live model portrayal verdict.

| Stable ID / character | Intended identity retained in the expansion specification |
| --- | --- |
| `bill_nye` — Bill Nye | Energetic, seasoned scientist; evidence and predictions; enjoys demonstrations and an audience; scientific enthusiasm is not mandatory cheerfulness. |
| `mr_apple` — Mr Apple | Older, convivial, nostalgic mathematics instructor; long anecdotal routes to answers; can monopolize a conversation and resent being rushed. |
| `ms_clocks` — Ms Clocks | Precise, composed, punctual instrumentation teacher; concise, organized, sometimes rigid and impatient with rambling. |
| `mr_phillips` — Mr Phillips | Serious practical technician; diagnostic hints, repeatable work, understated humor, and protection of personal time. |
| `mr_gusto` — Mr Gusto | Outgoing, mischievous performer; playful surprises and jokes, including the flaw of chasing a laugh too long. |
| `mr_hamstrings` — Mr Hamstrings | Talkative fitness/running enthusiast; repetition and tangents; exercise interests can exceed lesson preparation. |
| `mr_allu` — Mr Allu | Very reserved and awkward; comfortable with radios and reasoning; social hesitation and low classroom motivation remain real. |
| `bill` — Bill | Stern, shop-trained, demanding; orderly defensible work, restrained approval, dry humor, and stubbornness. |
| `chad` — Chad | Arrogant, dismissive, largely uncaring; success, ownership and financial independence matter more than teaching. His worldview affects ordinary judgments. Independence 0.96, arrogance 0.96, empathy 0.14, ambition 0.99 are explicit seed anchors. |
| `ms_bird_heart` — Ms Bird Heart | Affectionate, caring, warm and patient; privacy matters; she can be hurt and retain boundaries. Empathy seed 0.97. |
| `dr_volts` — Dr Volts | Eccentric older experimental scientist; anomalies and apparatus fascinate him, while sadness/fatigue can suppress enthusiasm. Curiosity seed 0.99. |
| `stanley` — Stanley | Elderly, tired, disengaged; decades of knowledge without exceptional motivation; quiet routines and crosswords. Teaching effort seed 0.08. |
| `ms_rivera` — Ms Rivera | Distracted designer; routine campus work competes with her own projects; capable but often unmotivated about teaching. |
| `mr_blake` — Mr Blake | Upbeat, playful, practical electronics instructor; safe experiments, curiosity, distractibility, and uneven organization. |
| `mr_stone` — Mr Stone | Authoritative, commanding, disciplined and strict; procedure and safety; can be rigid and intimidating. Discipline seed 0.99. |
| `josh_wildes` — Josh Wildes | Skeptical, critical, logic-oriented and argumentative; likes weak arguments less than reassurance; limited teaching motivation. |
| `bradley` — Bradley | Reserved, observant, methodical; deliberate dramatic pauses; slow trust and short answers when annoyed. |
| `jeff` — Jeff | Strict and focused in class, kinder and informal outside; practical garage interests, stubbornness, and earned generosity. |
| `mr_bro` — Mr Bro | Energetic masculine gym enthusiast; informal slang, short relaxed phrases, playfulness, confidence, arrogance and distraction. Teaching effort 0.28, slang 0.96, arrogance 0.67, professionalism 0.18 are seed anchors; no new fixed lifting record. |
| `brian` — Brian | Short-tempered, blunt and impatient; willing to argue, dislikes interruptions, enjoys strategy games. Anger sensitivity 0.98 and confrontation 0.88 are seed anchors. |
| `ms_lunch` — Ms Lunch | Brisk, earthy, practical dining worker; caring alongside strictness about the line, waste and extra work; no universal counseling role. |

These seeds remain readable while the configured AI develops the full prose and mood examples. Completed generated students supply every trait independently. Derived legacy values are retained only as compatibility/migration input and are not the new-student creation algorithm.

## Numerical personality and local behavior

The [complete 107-key numerical schema](dossier/trait-schema.json) includes independent social, emotional, motivational, communication, cognitive, teaching, and study values. Legacy names are retained where gameplay already uses them: `grudges` represents grudge holding, `slang` represents slang usage, and `teaching_effort` is the teaching-motivation value exposed through the classroom API.

The same trait dictionary reaches teacher disposition, student activity selection, emotional appraisal/recovery, social initiative, conflict, attention, routine work, motion and delivery. Local simulation handles routine walking, sitting, posture, work, phone use, boredom and recovery without an AI call. Refreshing an NPC at its existing decision cadence retrieves its authoritative projection. Opening the inspector is not a social event.

The assignment integration test deliberately establishes sharply contrasting independent traits in the authority, then observes actual work, sleep and phone poses, social initiative and scheduled submission. Altering only a stale profile copy no longer changes the canonical person; the historical tests were adapted to make their controlled fixtures explicit.

## Retrieval, consistency, and request size

Ordinary interactions combine compact core identity, current mood and relationship, relevant life sections, a few relevant style examples, recent turns, developing personal facts, and only applicable gameplay information. Dossier retrieval selects no more than four life sections and three examples. Situation, mood, relationship, generated topics/entities/aliases, related concepts, and actual recent conversational subjects affect ranking. A common language concept map supports paraphrases without a branch for each exact question or named character.

The dossier selector uses adjustable 2,400–18,000-character bounds, normally 6,500 characters for its own layer. These are structural size bounds, not token counts or a complete API-prompt budget. Whole sentences are chosen when a section is too large. The interaction/transport layers separately preserve identity-critical fields and remove irrelevant context. No remote embedding request is required for a simple local lookup.

The complete immutable life prose and developing fact ledger have separate roles. The ledger supports historical/current/preference records, links, revisions and provenance. Actual observed gameplay, hearsay, beliefs, academic knowledge, verified performance and relationship history retain their own authority. Existing records and relevant life paragraphs are supplied before a new personal claim. The interaction validator checks both spoken claims and proposed memory edits; suspicious conflicts can trigger a bounded semantic review rather than adding a validation request to every ordinary sentence.

Local checks cannot prove the truth or consistency of arbitrary natural-language prose. Initial generation requests a self-review and provides strong structural, numerical and immutable-identity validation. Detailed model coherence, long semantic chains and naturally varied mood expression still require live transcript review. Local concept matching also has a finite vocabulary; it is not a general embedding model.

## Executed verification and measurements

Dossier tests ran in isolated user-data directories with Godot **4.5.1 Mono**, the matching .NET runtime, and no OpenAI key. The three known Linux errors for the repository's Windows-only CEF extension remain baseline observations. The passing runs contain no script errors.

| Verification | Observed outcome |
| --- | --- |
| Dossier schema and semantic retrieval | PASS: teacher anchors, fresh Bro without a forced record, preserved migration, host separation, four bench paraphrases and a conversational follow-up, malformed dossier rejection, and immediate empty-reserve class selection. |
| Coordinated generation contract | PASS: one in-flight job, invalid section refusal, repair preserving completed life sections, durable publication, teacher deduplication, corrupted job metadata rejection, independent trait projection, and supplied usage accounting. Provider output is a synthetic contract fixture. |
| Concurrent personal canon and publication recovery | PASS, 40 assertions: an actual Brain update during a held request blocks stale teacher publication; one scoped repair preserves traits and unrelated examples; recovery rechecks canon; unchanged appearance survives transport while body edits fail; an oversized 80-record constrained request is held before HTTP. |
| Two-process dossier restart | PASS: separate writer/reader Godot processes preserve full identity, appearance, personality, beliefs, 107 traits, 34 examples, voice, supplied usage, and the pending repair draft. Interrupted generation requeues without losing completed work. |
| Population corruption recovery | PASS, 208 assertions: original damaged bytes, valid backup recovery, session identity, host isolation, and bounded unsaved cache. |
| Population profile binding | PASS, 17 assertions; explicit historical identities remain private to the correct host. |
| Population and discipline | PASS with 30 historical saved profiles; an exhausted reserve requests expansion without inventing people. |
| Actual classroom assignment autonomy | PASS, 561 assertions; distinct visible work/sleep/phone behavior, bounded social generation, accurate delivery/cancellation, and official human work unchanged. |
| Actual assignment NPC discipline | PASS, 25 assertions; real line-of-sight perception, visible phone prop, escalation and custody, and preserved academic clock. |
| Verified academic memories | PASS, 43 assertions through actual class, station and grader paths; own verified experience is retrieved for another listener without fabricating a player's performance. |
| Prior-learning integration | PASS, 69 assertions from persisted host outcomes to the real preparation path. |
| Public affect projection | PASS, 600 recovery frames; privacy filtering leaves actual public animation state and full-profile behavior intact. |
| Production Main process restart | PASS, writer 45 and reader 93 assertions in different operating-system processes; complete new biography ledger, all other memory, customized roster, private listener state and elapsed emotional recovery survive. |
| Real ENet host/client cases | PASS for facing, classmate, phone and human discipline; classmate rerun after the public-profile isolation fix preserves ordered speech, full affect and six-trait public privacy. |
| Asynchronous group contribution | PASS, 18 assertions; ungraded NPC helper membership, bounded generation, released-content privacy and cancellation when an actor leaves, becomes absent, is replaced or changes class phase. |
| Live configured-model acceptance | SKIP, exit 2, unavailable `OPENAI_API_KEY`. No generated-student diversity or natural-dialogue quality verdict is claimed. |

Logs and [dossier summary](dossier/summary.json) are under `dossier/`; [dossier restart results](dossier/process-restart/summary.json) identify both actual processes. The separate [Main restart/network report](RESTART_NETWORK_VERIFICATION.md) records complete gameplay persistence, public identity isolation, real ENet cases and the final consistency fixes. The native [facial report](FACIAL_VERIFICATION.md) includes before/after 12-panel renders, actual Main captures and separately counted geometry/ownership assertions. The [menu startup report](MENU_STARTUP_VERIFICATION.md) covers actual Singleplayer and Host Game Play, including pointer-driven native sessions with the production C# worker. The [HTTP report](HTTP_VERIFICATION.md) exercises the production client against a real local HTTP provider; its deliberately authored responses do not establish live inference cost or quality.

### Measured projection and retrieval cost

The full caller microbenchmark ran 500 profile lookups per case in one process, with the baseline modules from commit `7ec6c95241fca70e724783d6234dc3f445a6630c`. Retrieval used a validated synthetic six-section, 34-example dossier for 100 iterations. The complete log is [test_dossier_performance.gd.log](dossier/test_dossier_performance.gd.log).

| Measurement | Baseline | Updated |
| --- | ---: | ---: |
| Teacher profile lookup, microseconds/call | 61.570 | 36.028 |
| Student profile lookup, microseconds/call | 65.768 | 25.342 |
| Dossier retrieval, mean milliseconds | No corresponding old complete-dossier operation | 3.030 |
| Full fixture dossier | Not applicable | 21,617 bytes |
| Lightweight fixture profile | Not applicable | 9,175 bytes |
| Selected dossier context | Not applicable | 3,659 characters |

The teacher case uses the migrated authored seed; the student case uses a complete synthetic dossier. These are measured caller costs in this environment, not an FPS benchmark, maximum-population stress test, or live-generation benchmark. Character counts are explicitly reported as characters and are not converted into invented token usage.

The production HTTP test confirmed a foreground response completed while a delayed background generation was still active. The ordinary interaction used one text-generation request plus the two retained moderation requests; assessment boundaries or invalid drafts legitimately used an additional text request. See the HTTP report for exact fixture timings and accounting evidence.

### What remains unmeasured

Actual model generation time, real input/output-token averages, inference cost, real voice response latency, natural dialogue across every teacher and mood, and simultaneous multiplayer model-load performance require configured live credentials. The approximate 1,000–3,000-input-token goal has **not** been claimed as achieved. Persistence, local lookup cost, real HTTP scheduling, native classroom behavior, model rendering and startup have separate evidence; they do not substitute for live conversational quality.

## Reproduction

Use the Mono Godot executable and matching `DOTNET_ROOT` for the full project. Give each test a fresh `XDG_DATA_HOME` and avoid a real player's saves.

```sh
godot-mono --headless --path . --script res://tests/campus/academics/dossier/test_dossier_schema.gd
godot-mono --headless --path . --script res://tests/campus/academics/dossier/test_dossier_generation.gd
godot-mono --headless --path . --script res://tests/campus/academics/dossier/test_dossier_canon_race.gd
godot-mono --headless --path . --script res://tests/campus/academics/dossier/test_dossier_performance.gd
python3 tests/campus/academics/dossier/run_dossier_process_restart.py --godot /path/to/godot-mono --dotnet-root /path/to/dotnet --output /fresh/evidence/path
```

The performance script reports a baseline only when baseline modules are prepared under the ignored `.godot/dossier-baseline/` directory. Without those modules it still records current costs and explicitly leaves the baseline result empty. Full gameplay scripts are under `tests/campus/academics/`; startup reproduction is documented in `tests/menu_startup/HANDOFF.md`.

With real configured credentials and an isolated test host, `test_live_character_acceptance.gd` drives the actual bounded generator until all established teachers have completed dossiers and at least three genuinely AI-generated students are available, then exercises the conversation pipeline. It exports complete transcripts, generation evidence and provider measurements. Its fixtures are not substituted when the service is unavailable.
