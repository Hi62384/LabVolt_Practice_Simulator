# MTH147 postreview v3 — incomplete integration candidate

This nonlaunch verifier binds predecessor receipt paths and SHA256 bytes to the exact frozen v7 plan, then checks accepted outcome, explicit TEST-INSTRUMENTED HOST labeling, historical snapshot L, normal-zero and Job0 cleanup, no hold/errors, and full post-run inventory count. It rejects boolean Job counts and parser exit codes. The preserved v2 validator supplies request ID bounds, digest/type validation, privacy coverage and actual output absence checks.

No actual predecessor receipt hashes can be issued before those stages execute. The required predecessor descriptor is the exact planned RESULT.json path, its actual SHA256, and durable=true from successful runner publication. A caller-supplied descriptor alone never passes without reading matching result bytes.

This is incomplete: frozen v7 does not emit evidence_label, and its on-disk receipt deliberately carries durable=false. A separately reviewed source-only runner change must emit the explicit label while retaining snapshot L and preserve independent successful-publication evidence. Do not treat this packet as admission ready or launch it. No grant is created and no engine is run.
