# Custom character voices — implementation and acceptance

Scope: permanent original fictional adult character voices only. The implementation builds on the existing combined character-dossier and audio changes. No new Realtime conversation, general transcription, image, or memory-embedding functionality is included.

## Using the feature

1. Open **OpenAI Settings → Character Voices** with your host API key configured.
2. Select **Generate missing faculty voices** and explicitly continue. The batch creates up to one new prompt-generated candidate per missing faculty member, skips already approved/pending characters, and stops after the current request if canceled. All 21 established characters have authored acoustic designs; generated adults receive dossier-derived designs.
3. Select a candidate. Use **Play all 3 core auditions** (normal, sad, angry). Each preview is an explicit paid speech session. Compare the same speaker and the same script; auditioning is not approval.
4. If satisfied, check the listening confirmation and **Approve voice and model**. **Next candidate** advances to another pending person. The approved resource ID and model persist, including when the global speech model changes.
5. If a creation result is uncertain, inspect the correct OpenAI project's dashboard for the unique journaled resource name. Recover its actual ID as an unapproved candidate, or explicitly confirm that no resource was created before clearing the journal. Do not repeat ambiguous POST requests.

Prompt-to-voice generation itself is free; the speech auditions are billed at GPT-Live session rates. The documented organization limit is 100 prompt-generated voices; the separate recording-based limit is 20 for eligible accounts. The game maintains a conservative local allocation ledger plus an explicitly entered external count. This is not a provider quota lookup. Recording-based IDs may be imported only with the host's explicit authorization and audition; this implementation does not collect consent recordings or create cloned recording-based voices.

## Persistence and routing

- Stable identity is separate from temporary emotion, relationships, and delivery. Preset matching uses vocal description and traits, not roster order or a modulo voice assignment.
- Existing approved IDs remain unchanged. A candidate never replaces gameplay speech before explicit approval; prompt voices route through compatible GPT-Live models rather than conventional TTS or Realtime.
- New generated-character records are scoped to the saved host campus. An ambiguous preexisting unscoped ID requires explicit adoption or separate initialization. Established faculty remain installation-wide.
- Allocation intent is persisted before POST; a crash, uncertain response, or save failure does not silently permit a duplicate. A corrupt primary store fails closed; backup and temporary files are preserved for deliberate recovery, never silently substituted for a possibly newer approved voice.
- Audition evidence is scoped to the actual voice, model and script hash. Old approved voices remain approved; old audition records without model/script evidence cannot newly approve a candidate. Provider resource IDs are not exposed in selected-character inspection packets.
- Model access errors for a custom resource do not automatically mark its entire model inaccessible; specialized access can be tested by an explicit audition. Keys remain host-side.

## Verification and limitations

The code contains regression coverage for authored voice coverage, expressive delivery, stable IDs, model-specific approvals, stopped auditions, batch provisioning, retry avoidance, interrupted creation recovery, quota accounting, legacy adoption, and cross-campus separation.

Native Godot/.NET and a real provider account were unavailable in this session; the local Windows command tunnel was offline. The native tests are committed but not executed here. No actual account-owned custom voice IDs have been generated, no teacher has been acoustically auditioned or marked approved by the assistant, and no live API access or output quality is claimed. The host must execute the batch and judge the auditions in-game. The implementation is distinct from real-provider acceptance.

Official contracts checked November 27, 2026:
- https://developers.openai.com/api/docs/guides/custom-voices
- https://developers.openai.com/api/reference/resources/audio/subresources/voices/methods/create/
- https://developers.openai.com/api/docs/guides/live

Run targeted native fixtures on an imported/built Godot Mono project:
```
python tests/campus/academics/run_voice_pipeline_tests.py --godot <Godot-console-executable> --logs <log-folder> --cases test_character_voice_identity test_character_voice_studio test_custom_voice_recovery
```
