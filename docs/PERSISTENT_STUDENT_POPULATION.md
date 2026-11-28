# Persistent campus students

## Identity and admission

New students use `campus_student_` followed by 128 cryptographically random bits. The originating player profile is recorded as a SHA-256 namespace; a temporary multiplayer peer number is never a permanent identity. Historical numeric IDs retain their original local memory keys. On transfer, their origin namespace and historical ID produce a stable 128-bit alias, so two devices' `campus_student_00` records remain different people.

The existing local population and dossier stores remain authoritative saved identities. `academic_programs.gd` is the single program/course mapping, exposed by `CampusCourseProvider.programs()` and `program_courses()`. There are currently no academic prerequisite rules; suspended or withdrawn NPC enrollment excludes attendance. Official player marks are never imported through population records.

Class selection filters the combined ready collection by course and current activity, then uses weighted sampling without replacement for at most six students and the actual available room capacity. Familiar classmates receive a modest preference, academic motivation influences attendance, and occasional course-specific background generation refreshes the reserve. Generation seeds fix the chosen program and compatible courses. Existing identities are never rerolled.

## Session exchange

`StudentPopulationSync` uses authenticated session identities and reliable host-authoritative RPCs. Clients retain their own population on disk. The host requests index pages of 32 bounded entries, then fetches complete dossiers only for a small eligible reserve. A complete profile is accepted only in response to a pending request. Peer identity changes invalidate outstanding work. Already admitted students remain saved on the host when their originating player disconnects.

A selected dossier carries fictional identity, life history, personality, speech examples, appearance and voice design. Custom voice identifiers and compatibility can travel separately; account access is marked unverified on a new device. Audition journals, account allocation budgets and credentials never travel. Client-local legacy aliases are resolved before reading or writing social records.

## Reconciliation

Profile revision numbers are advisory, not permission to rewrite a character. An existing name, age, role, program, appearance or established biography section is preserved if a contribution contradicts it. Nonconflicting additional life-history sections can merge. Conflicts are retained in diagnostics instead of silently choosing the largest timestamp or version. Duplicate global IDs do not create duplicate students.

Social receipts include only one NPC and the relevant participant. Human recipients receive only their own relationship history. NPC-to-NPC bonds contain no human conversation record. Portable social records exclude official academic outcomes, marks, raw audio, full chat transcripts and privileged game state. Bounded significant episode summaries and reported personal facts remain untrusted observations inside character context.

Each social receipt includes a normalized JSON digest, a local revision and bounded parent-digest ancestry. An exact repeat is idempotent; an ancestor is stale; a descendant can replace the scalar relationship state. Concurrent branches preserve the current host's scalar relationship and decision, merge unique episodes and nonconflicting facts, and record a conflict. A later observed interaction can reconcile a disputed personal claim. Wall clocks do not decide authority. Approved voice conflicts retain the existing voice and require explicit resolution.

Population, dossier, social and memory writes use temporary files, validation, backup and rename. Corrupt snapshots are preserved; a valid backup can recover known identities. Social receipts can repair a missing main memory snapshot after an interrupted multi-file save. Storage limits return errors rather than silently deleting established characters.

## Verification

`test_student_population_portable.gd` exercises real persistence and JSON transport with synthetic historical dossiers, independent origin namespaces, eligibility, duplicate/conflicting profiles, friendship and significant memory restoration, privacy filtering and causal updates. These fixtures do not claim AI generation quality or physical Windows gameplay verification.
