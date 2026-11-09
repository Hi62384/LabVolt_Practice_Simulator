# MTH147 v7 post-review correction proposal v2

Classification: reviewer-owned source-only proposal. This is not a grant, reservation,
parser result, or behavioral acceptance result. The frozen v7 and original post-review
packages remain unchanged.

The original readiness model accepts self-asserted booleans instead of inspecting the
exact plan output path and accepts a minimal fabricated predecessor dictionary. It also
does not strictly type or format several request-context fields, accepts `False` as a
zero private-field count, and applies the behavioral cleanup schema to the parser even
though the runner stores parser cleanup in `backend.cleanup`.

`admission_readiness_v2.py` is a correction proposal. It:

- rehashes the exact frozen plans, source/cache lock, runner, fixture, caller, Main
  preimage, engine, Python, every plan-bound helper, and every project lock entry;
- requires every frozen path to stay within the expected package/project roots;
- checks the actual plan output and `RESULT.json` paths are absent before admission;
- requires a durable, hash-bound predecessor receipt from the exact prior plan and lock,
  including normal-zero, Job0, source/cache-after, and evidence-label proof;
- strictly validates request IDs, SHA-256 strings, assessment/profile identifiers,
  integer IDs, privacy counts, and the submit operation;
- uses the parser's real `backend.normal_exit` and `backend.cleanup` schema, while
  retaining the behavioral `cleanup` schema for solo and two-peer receipts;
- requires receipts to carry the `TEST-INSTRUMENTED HOST` evidence label. The current
  runner does not emit that top-level label, so runner-owner review is required before
  controlled runtime.

Run only the lightweight regressions:

```powershell
& 'C:\Users\User1\AppData\Local\Programs\Python\Python311\python.exe' -B -m unittest -v test_admission_readiness_v2.py
```

