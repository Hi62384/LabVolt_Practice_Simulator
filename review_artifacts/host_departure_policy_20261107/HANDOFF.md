# Host departure policy

Apply `host_departure.patch` from the project root after matching all three files to `PREIMAGES.sha256`. The patch SHA-256 is `21DB632282BF09BB68AE0BB49CF589C7CFD0E4E4A1FBC48862267C6548D66035`.

- `school_session.gd` records the authority role on each assessment obligation at enrollment and sheet issuance. Normal host exit closes the current assessment before roster teardown. Startup reconciles the old archive before selecting a profile. Recovered host results enter the local gradebook only for the matching profile and only if that result is missing.
- `pending_assessment.gd` atomically replaces unfinished host obligations with an official zero under the same attempt and curriculum IDs. It removes unscored guest obligations without recording a mark, completion or reward. Existing official results stay in the archive. Earlier untagged obligations lack a durable role and are retired without a grade. This is the conservative handling for legacy entries because using the current local profile as a proxy could fail a guest. No class state is restored.
- `session.gd` routes the client `server_disconnected` signal explicitly to lost-authority handling. A host whose whole local transport reports disconnected goes through normal leave and skips individual roster removal callbacks while that transport is disconnected. A single peer loss while the server transport still reports connected keeps the existing individual departure behavior. ENet does not reveal which side caused an arbitrary partition, so it cannot retrospectively distinguish such a loss from a remote player departing.

The patch preserves the existing archive writer and idempotent grade IDs. If a close write fails, the archive remains pending and the next process startup retries reconciliation. Abrupt process exit is handled from durable obligations at startup, including a window close that bypasses ordinary leave. Existing completed results are excluded from reconciliation.

Verification scope is source review, hashes and patch applicability. No engine, automated tests or live save operations were performed.
