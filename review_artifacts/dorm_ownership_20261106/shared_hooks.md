# Dorm ownership shared-hook handoff

No shared file was edited. Apply these hooks only after verifying the exact SHA-256 preimages below. If a hash differs, re-review the anchors instead of applying mechanically.

## Verified source boundaries

- `scripts/session.gd` SHA-256 `4c5bd463b7bf6ec6627e8070698528ac183ca7eb328c14af5358feb001c64cde`
- `scripts/inventory_authority/network.gd` SHA-256 `84c67f67243786565ec64bce941c0d20d0761895bef54eb316805c5c7f103175`
- Dorm authority owns only `scripts/campus/dorms/authority/`. Tests own only `tests/campus/dorms/authority/`.

## Session capacity and lifecycle hook

The verified capacity preimages in `scripts/session.gd` are:

```gdscript
var error := peer.create_server(port,7)
```

and:

```gdscript
if roster.size() >= 8 or roster.has(id):
```

The effective maximum is therefore 8 (seven remote clients plus host peer 1). The shared owner should expose one constant such as `const MAX_PLAYERS := 8`, use `MAX_PLAYERS - 1` for `create_server`, and use `MAX_PLAYERS` for the registration bound. Pass this exact value to `DormAuthorityNetworkAdapter.configure(world_provider.stable_dorm_ids(), session.MAX_PLAYERS, session_epoch)`; configuration intentionally fails unless the world returns eight unique stable IDs.

After host initialization has authenticated host peer 1 in `roster`, call `authenticated_join(1)`. In `register`, only after the peer has been accepted into `roster`, call `authenticated_join(id)`. In `_left`, synchronously call `authenticated_leave(id)` before or alongside roster erasure. On `leave()`/restart, begin a new monotonically different session epoch and reconfigure; never restore old room ownership from a save.

For reconnect/initial sync, call `reconcile()` against the authenticated connected roster, then `initial_snapshot(id)`. The adapter's `peer_is_connected` binding should call the existing `peer_connected_now(peer)` so stale roster entries cannot retain rooms.

## Door request transport hook

Add one reliable any-peer RPC on the shared session/network owner whose body ignores any claimed identity and invokes:

```gdscript
if multiplayer.is_server():
    dorm_authority.receive_door_request(multiplayer.get_remote_sender_id(), request)
```

Host-local interaction invokes the same method with peer 1. Client requests contain only `{epoch, sequence, open}` (an echoed `room_id` is allowed only as a consistency check). Bind `broadcast_snapshot` to an authority-only reliable RPC and reject snapshots on clients unless `multiplayer.get_remote_sender_id() == 1`. Replicate the adapter snapshot as-is; do not append profile, notes, loadout, inventory, credentials, or save fields.

The world/interaction owner consumes `assignments` for labels/owner interaction prompts and `open_doors` for physical door state. Only an assigned owner gets an open/close interaction. Passage through an open door is public and must not be collision-locked to the owner. Room entry must not call any private-data accessor.

## Integration safety

The dorm adapter is deliberately separate from `scripts/inventory_authority/network.gd`. Do not route dorm visitation through inventory enrollment or expose its credentials. Existing profile privacy projection remains the only public profile path. Shared-owner integration should rerun the two offline dorm suites plus existing session, profile privacy, inventory authority, and interaction tests.
