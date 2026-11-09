# Avatar collectible persistence fixtures

`test_profile_adapter.gd` is an isolated fixture suite. It uses an in-memory
profile double and JSON encode/decode for round-trip coverage; it never opens or
modifies a real `user://` profile.

The suite covers fresh and legacy migration, missing starter grants,
idempotence, unrelated-field preservation, authority rejection, unknown IDs,
malformed properties, duplicate permanent purchases, atomic rollback, shared
equipment reads, body-only edits at the current 0.65-1.4 bounds, optional and
required-slot unequip policy, atomic multi-change editor edits, validation of
the real four catalog files, the real AvatarCore callable seam, and JSON
persistence shape.

It is intentionally not an engine/network acceptance test. The main integrator
must wire the adapter into the existing authoritative ledger transaction as
described in the handoff.
