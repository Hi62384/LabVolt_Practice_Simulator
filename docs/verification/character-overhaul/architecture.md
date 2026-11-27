# Character architecture and requirement coverage

Implementation snapshot: 2026-11-27; character memory schema **7**, population schema **1**.
This maps the request's 34 sections to implementation and focused tests.
Human-quality acceptance and blind identification remain unverified. The accompanying
verification report contains run results and transcript excerpts.

## Authoritative identity and interaction flow

[Profiles] combines the established roster, authored personas, independent traits,
knowledge domains and [worldviews]. Saved students retain identity, appearance,
voice and profile. The classroom adapter derives older teaching fields from this
profile. Saved belief revisions supersede older examples on the same subject;
core motivations remain stable.

[Faculty] connects direct text/voice conversations, student conversations, formal
teaching, visual explanations, announcements, office hours, staff handoffs and
observed classroom reactions to [Interaction]. Specialized callers add observations,
current teaching material or supported actions to its common context.

The shared path validates the host and activity, moderates input when connected,
then requests structured semantic interpretation. It checks the captured host
profile and caller validity after awaits, before applying affect. [Mind] updates
the emotional state and selects a strategy using [Behavior]. Generation receives
the resulting full state, decision, knowledge restrictions and retrieved memories.
Invalid interpretation selects explicit offline recovery.

Before delivery, the host validates speech, assessment restrictions, biography and
belief proposals. Supported actions require real host execution; a proposed or
started action is not a completed action. Recording uses an event identifier and
actual delivered speech. Listening, intentional silence and sanitized moderated
incidents retain perceived events. Completing a previously observed event adds
speech without replaying its relationship effect. Stale requests are cancelled.
Disengagement stores individual intentions, not a universal 20-second lockout.

## Context, presentation and bounded requests

[Host transport] separates trusted instructions from JSON containing context and
untrusted player dialogue. Interpretation and speech use the configured model and
effort. Their output budgets are respectively 900–2,048 and 1,400–4,096 tokens;
visual speech starts at 1,800. Timeouts are 18 and 24 seconds. Input dialogue is
limited to 1,000 characters; serialized character input to 24,000; instructions to
20,000. Context reduction removes lower-ranked memories and older turns while
preserving identity, beliefs, current affect and at least four selected turns when
available. Irreducibly oversized requests fail explicitly. Generation permits at
most two attempts.

Malformed responses, output-token exhaustion and text exceeding 16,000 characters
are errors. Separately, [speech] limits delivered speech to 1,600 characters at a
complete sentence boundary; an overlong first sentence is rejected. This remains
a presentation ceiling. Subtitle paging preserves the accepted text. The [HTTP
test] checks actual loopback requests, ordering, separation, reduction and failure
handling; its provider content is deliberately deterministic.

All 16 affect values and recent experiences reach generation. [Motion] combines
affect and traits with face, gaze, posture and gestures. Voice delivery receives
personality/emotional parameters; synthesis depends on engine availability.
[Visual evidence] covers native static states, not every walking/speaking combination
or audible emotional performance.

## Persistence, relationships and population

[Memory] owns directional relationships, conversations, descriptive episodes,
reported facts, character biographies, affect snapshots, event receipts and belief
revisions. Thirteen relationship dimensions develop independently. Trust does not
automatically recover with time; acute annoyance and persistent resentment have
different recovery rates. Legacy counters remain compatible with older callers.

Reliability and lab safety start at neutral **0.5**, bounded to **0–1**. Verified
assessment/quiz completion, practical results and perceived physical hazards affect
reputation. Weak submitted work demonstrates follow-through while lowering academic
confidence; an incorrect measurement does not establish misconduct. Speech cannot
award verified academic reputation. [Academic evidence] covers NPC grading and AC
stations; [human outcomes] covers accepted practice, quizzes and room/formal
assessment submission, preserving grades, privacy, directional ownership and receipts.

Host namespaces use a SHA-256-derived prefix under `user://character_memory/` for
memory, population and learning files. Character/speaker pairs retain distinct
histories; personal biography and revised opinions belong to the character across
listeners. A single legacy-owner marker prevents copying old private data into
every host profile. Memory versions 1–6 migrate to version 7. Profile switching
exports the bound mind even if no conversation marked memory dirty.

Memory and population writes use flushed temporary files, validation, a valid
backup and replacement. Two corrupt copies block replacement and expose unsaved
status. Session progress remains in RAM; bounded identity-keyed caches allow host
switching without transferring that progress to another profile. These caches are
not durable and do not silently evict entries. [Population] also preserves damaged
file bytes under content-addressed corruption filenames before repair from a good
copy. When neither copy can be read, any fallback roster is session-only; unknown
customized identities cannot be reconstructed. Invalid namespace selection fails
closed in classroom binding.

### Retention and retrieval limits

| Stored material | Current bound |
| --- | --- |
| Relationship pairs / conversation containers | 2,048 each |
| Per pair: exchanges / event receipts / episodes | 4,096 each |
| Per pair: reported facts | 2,048 |
| Character biographies | 2,048 characters; 2,048 topics each |
| Belief revisions | 2,048 characters; 64 beliefs each; 4,096 revisions per belief |
| Working affect | 64 experiences per character; latest 12 supplied in context |
| Mind event cache | Latest 1,024 events; durable memory receipts are separate |
| Memory snapshot / population snapshot | 128 MiB each |
| Unsaved host cache, per subsystem | Eight inactive profiles and 128 MiB total |
| Campus population | 24 initially, expandable to 4,096; original 12 IDs retained |

Persistent-history bounds report errors rather than evicting old stories.
Routine retrieval selects the latest 12 exchanges plus up to four ranked older
exchanges, then restores chronology; it also selects eight facts and eight episodes.
Students receive up to eight own verified academic experiences. Ranking combines
recency, importance, semantic-stage domain, predefined concept groups and word
overlap. There is no embedding index; arbitrary paraphrase recall remains limited.

[Summaries] derives four topic views with counts, timestamps, source excerpts and
unanswered questions. Each retains up to two notable episodes, two reported facts,
two unanswered questions and the latest exchange. Originals remain intact;
completion removes the corresponding unanswered marker. Assessment context omits
these excerpts before interpretation and generation. [Summary tests] verify
grounding, privacy and reconstruction after reload.

Verified academic patterns expose course/week strengths, difficulties and trends,
using at most 12 recent outcomes and eight recent weeks per course. A single error
does not establish a weakness; correctness alone never diagnoses a misconception.
[Knowledge] uses bounded personal practice evidence for ordinary course familiarity,
preserving specialist, current-information, calculation and assessment restrictions.
[Prior-learning tests] follow persisted outcomes into the actual next prepared turn.

## Belief and biography guarantees

[Beliefs] accepts revisions only to existing belief IDs, with current-input quoted
evidence, a nonempty reason and a position present in delivered speech. The pipeline
rejects duplicate IDs, more than two updates, reused evidence and excessive
conviction changes. Openness, conviction, importance and accumulated evidence gate
position changes. Profession and core personal-priority positions are protected.
Full revision chains persist; the latest six reasons accompany effective beliefs.

These checks cannot prove an argument true, relevant or logically persuasive.
An open, uncertain character can revise a position in one exchange. Biography
validation checks canonical topics, delivered details and exact saved conflicts;
paraphrased contradictions can escape detection. Neither mechanism establishes
course facts, measurements or grades. [Evolution tests] exercise delivery and
persistence gates through the shared pipeline with deterministic provider replies.

## Mapping the 34 requested sections

“Coverage” below names implementation and tests, not a human-quality pass.

| Section | Coverage and remaining qualification |
| --- | --- |
| 1. Overall objective | Integrated routes and [gameplay tests]; believable-human acceptance remains open. |
| 2. Architectural audit | [Interaction], [Mind], [Memory], [Profiles] replace the identified shared bottlenecks. |
| 3. Beliefs/worldviews | [Worldviews], [Beliefs], [belief tests]; grounding limits above apply. |
| 4. Chad | Always-active worldview and ambition decisions; [worldview tests] and actual [traces]. |
| 5. Established teachers | Authored profiles/overrides for all 21; [gameplay tests] compare actual routes. |
| 6. Disagreement | [Behavior] selects defense, challenge, reconsideration and agreement from context. |
| 7. Disrespect | Distinct evolving strategies and offline recovery; [reaction tests]. |
| 8. Disengagement | [Mind] evaluates apology, topic change and urgency; silent incidents persist. |
| 9. Semantic ordering | [Interaction] interprets before affect/generation; [pipeline tests], [HTTP test]. |
| 10. Moderation | Sanitized incident semantics preserve appraisal and recording; [pipeline tests]. |
| 11. Assessments | Shared AI route with private-content filtering and output restrictions; [gameplay tests]. |
| 12. Variation | Recent turns and repetition inform strategy/generation; fallback banks remain finite. |
| 13. Speech style/length | [Behavior] instructions and [speech] replace the 300-character instruction; 1,600-character ceiling remains. |
| 14. Emotion | Full affect/history, elapsed recovery and persistence; [memory tests]. |
| 15. Body language | [Motion], [visual evidence], [public-affect test]; comprehensive audiovisual observation remains pending. |
| 16. Relationships | Independent directional dimensions affect willingness/social selection; [memory tests]. |
| 17. Reputation | Verified academic/lab outcomes, safety and social history; [academic evidence]. |
| 18. Long memory | Retained originals, extractive topics, academic patterns and atomic saves; [summary tests], [resilience tests], [migration tests], [process restart]. |
| 19. Biography | Specific canonical facts across listeners/reload, pre-delivery conflict rejection; [evolution tests]. |
| 20. Knowledge limits | Semantic domain/difficulty and bounded verified previous learning; [Knowledge], [prior-learning tests]. |
| 21. Goals/autonomy | [Behavior] priorities and [Social] initiative use local simulation; actions and planning horizons remain bounded. |
| 22. Population | Persisted expandable [Population], occupancy exclusion and six-seat cap; [population tests], [corruption tests]. |
| 23. Student behavior | [Students] supports props, gestures, routes and individual assessment activity; [assessment test]. |
| 24. NPC conversations | [Social]/[Faculty] use shared generation and directional listening records, with throttling. |
| 25. Discipline | Shared [Discipline], real item custody/removal and host guards; [discipline tests], [human-network test]. |
| 26. Every route | Shared [Faculty] context including formal teaching and visuals; [classmate integration], [pipeline tests]. |
| 27. Prompts/transport | Full instructions/state, separated trust, bounded retry and explicit failure; [HTTP test]. |
| 28. In-world identity | [Mind] instructions and observed capabilities; provider behavior still needs live review. |
| 29. Classroom preservation | Existing lesson, grading and station authorities remain; [classmate integration], [academic evidence]. |
| 30. Diagnostics | Faculty/Interaction snapshots expose profile, decisions, context, source, execution and persistence status. |
| 31. Better tests | [Reaction tests] remove universal closure expectations; deterministic checks state their limits. |
| 32. Multi-turn acceptance | [Gameplay tests] and [traces] cover all teachers/representative students offline; blind human review pending. |
| 33. Live verification | [Live harness] records model/configuration/transcripts, exits 2 without credentials; no live pass claimed. |
| 34. Final acceptance | Implementation evidence is available; actual conversational quality remains the acceptance criterion. |

Academic outcomes do not establish specific misconceptions. Routine autonomy uses
supported actions and priorities with bounded planning. Live credentials were
unavailable. The optional live harness and blind-review export still need execution
and human assessment; fixtures and offline transcripts cannot establish that result.

[Profiles]: ../../../scripts/campus/academics/class_character_profile.gd
[worldviews]: ../../../scripts/campus/academics/character_worldview.gd
[Faculty]: ../../../scripts/campus/academics/faculty.gd
[Interaction]: ../../../scripts/campus/academics/character_interaction.gd
[Mind]: ../../../scripts/campus/academics/character_mind.gd
[Behavior]: ../../../scripts/campus/academics/character_behavior.gd
[Host transport]: ../../../scripts/campus/ai/host_openai_client.gd
[speech]: ../../../scripts/campus/academics/character_speech.gd
[HTTP test]: ../../../tests/campus/ai/test_character_http_transport.gd
[Motion]: ../../../scripts/campus/academics/character_motion.gd
[Visual evidence]: visual-check.md
[Memory]: ../../../scripts/campus/academics/character_memory.gd
[Summaries]: ../../../scripts/campus/academics/character_memory_summary.gd
[summary tests]: ../../../tests/campus/academics/test_character_memory_summaries.gd
[prior-learning tests]: ../../../tests/campus/academics/test_character_prior_learning.gd
[Academic evidence]: ../../../tests/campus/academics/test_character_academic_memory.gd
[human outcomes]: ../../../tests/campus/academics/test_character_human_academic_memory.gd
[Population]: ../../../scripts/campus/academics/student_population.gd
[Beliefs]: ../../../scripts/campus/academics/character_beliefs.gd
[Evolution tests]: ../../../tests/campus/academics/test_character_evolution_pipeline.gd
[gameplay tests]: ../../../tests/campus/academics/test_character_gameplay_overhaul.gd
[belief tests]: ../../../tests/campus/academics/test_character_beliefs.gd
[worldview tests]: ../../../tests/campus/academics/test_character_worldviews.gd
[traces]: offline-dialogue-traces.json
[reaction tests]: ../../../tests/campus/academics/test_character_reactions.gd
[pipeline tests]: ../../../tests/campus/academics/test_character_interaction_pipeline.gd
[memory tests]: ../../../tests/campus/academics/test_character_memory_v5.gd
[public-affect test]: ../../../tests/campus/academics/test_character_public_affect.gd
[resilience tests]: ../../../tests/campus/academics/test_character_memory_resilience.gd
[migration tests]: ../../../tests/campus/academics/test_character_memory_migration.gd
[process restart]: ../../../tests/campus/academics/run_character_process_restart.py
[Knowledge]: ../../../scripts/campus/academics/character_knowledge.gd
[Social]: ../../../scripts/campus/academics/classmate_social.gd
[population tests]: ../../../tests/campus/academics/test_student_population_and_discipline.gd
[corruption tests]: ../../../tests/campus/academics/test_student_population_corruption.gd
[Students]: ../../../scripts/campus/academics/classroom_students.gd
[assessment test]: ../../../tests/campus/academics/test_assignment_student_behavior.gd
[Discipline]: ../../../scripts/campus/academics/classroom_discipline.gd
[discipline tests]: ../../../tests/campus/academics/test_student_discipline_routes.gd
[human-network test]: ../../../tests/campus/academics/test_human_discipline_network.gd
[classmate integration]: ../../../tests/campus/academics/test_classmate_lab_and_dialogue.gd
[Live harness]: ../../../tests/campus/academics/test_live_character_acceptance.gd
