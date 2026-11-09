# Eight-participant V7 validator correction v1

Private integration candidate only. The owner package at `C:\Users\User1\Documents\Codex\2026-11-05\task-6\eight_participants_v7` was not modified. No engine, network, port reservation, or grant operation was performed.

## Integration scope

Replace only `path_contract.py` and `admission_contract.py` in a new versioned owner package. The candidate files preserve the parser receipt checks while closing the two independently reproduced validator gaps.

`path_contract.py` now requires exact canonical runner, lock, backend, output, parser-result, predecessor-result, fixture, and root-grant paths; it rejects missing bound files, outside-stage paths, absolute source/cache relatives, and repeated-suffix paths.

`admission_contract.py` now binds these exact lifecycle tuples:

| Course | Name | Port | Week | Kind | Predecessor |
|---|---|---:|---:|---|---|
| ELM253 | CLASSROOM-EIGHT-V7-ELM253-LIFECYCLE1 | 27096 | 1 | lab | none |
| ETY155 | CLASSROOM-EIGHT-V7-ETY155-LIFECYCLE1 | 27097 | 1 | lab | ELM253 |
| MTH147 | CLASSROOM-EIGHT-V7-MTH147-LIFECYCLE1 | 27098 | 6 | lecture | ETY155 |
| MTH255 | CLASSROOM-EIGHT-V7-MTH255-LIFECYCLE1 | 27099 | 1 | lecture | MTH147 |

All course tuples additionally require difficulty 0, eight participants, eight Jobs, one process per Job, and a 300-second envelope. The parser retains its exact one-engine, no-port, 30-second envelope.

## Verification

Owner suite, unchanged:

```text
Ran 11 tests in 1.938s
OK
```

Correction suite:

```text
Ran 8 tests in 4.595s
OK
```

The correction suite uses all five owner plans as positive controls. Negative cases cover the two original reproductions, outside output/predecessor/parser/grant paths, a missing bound file, a repeated directory suffix, and mutations of every course tuple field.

## Integrator procedure

1. Verify the original and candidate hashes in `HASHES.json`.
2. Apply the two patch files to a new versioned copy of v7, or copy the two candidate modules exactly.
3. Copy `test_validator_correction.py` into that new package and update its `OWNER` reference if the new package should become the positive-control source.
4. Regenerate every plan's bound-file hashes, plan hashes, `COMMANDS.json`, source lock if applicable, and ownership/static manifests. Existing v7 grants or plan hashes must not transfer.
5. Run the full owner suite plus the correction suite before any parser admission review.

The patch headers contain absolute review paths because they were produced with `git diff --no-index`. The candidate modules are the canonical integration payloads.
