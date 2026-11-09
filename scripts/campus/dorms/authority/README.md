# Dorm authority contract

`DormOwnershipAuthority` is pure host state. Configure it once per session epoch with the world provider's ordered, stable dorm IDs and the session's actual maximum participant capacity. The count must match exactly. Allocation is deterministic by authenticated peer order and world-provider room order.

`DormAuthorityNetworkAdapter` must receive peer IDs only from the host's transport/session callbacks. A client payload contains `{epoch, sequence, open}` and may optionally echo its assigned `room_id`; it never chooses the acting identity. Duplicate sequences return the cached authoritative result, older messages and old epochs are rejected, accepted requests are rate-limited, and disconnect cleanup closes and releases the room.

Public replication is deliberately compact: `{schema, epoch, revision, capacity, assignments:[[peer,room_id]], open_doors:[room_id]}`. It grants only physical door/entry state. Notes, loadouts, profiles, inventories, credentials, and other private room data must remain on their existing owner-scoped channels. Anyone may cross an open door; callers must not use room occupancy as a visitor collision lock.

Required shared hooks are staged in `review_artifacts/dorm_ownership_20261106/shared_hooks.md`; this directory does not modify shared session, main, player, profile, ledger, or registry files.
