Preimage `scripts/rolling_chair.gd` SHA256: `F2B85492A08AE458E84BF2B1A76A4E3FE01EEE64A1CC68610C3A74758D46AA39`.

Apply `rolling_chair.patch` only if that preimage still matches. The existing goal decay of `0.18 * delta` can leave a large positive spin goal for many seconds after mouse input stops. The patch exponentially damps the goal and actual angular velocity when there is no new turn input. Both the local rider and host follow the same path; remote observers continue to receive host chair state. The `0.002` stop threshold prevents endless tiny motion. Ctrl and head yaw remain in the existing player path.

Pending: main integrator applies the shared patch, then an isolated dynamic chair fixture checks release at multiple physics rates and opposite-direction braking. No engine process was run in this lane.
