# Dorm personal workstation integration

Shared files were not edited. `shared_hooks.patch` is bound to the `scripts/game.gd` SHA-256 in `PREIMAGES.sha256`; reject or rebase it if that hash differs.

## Owner integration

After the host-backed dorm ownership provider exists, create and configure the router:

```gdscript
dorm_interactions=preload("res://scripts/campus/dorms/interactions/personal_station_router.gd").new()
add_child(dorm_interactions)
dorm_interactions.configure(self, dorm_ownership_provider)
```

The provider must expose `room_for_peer(peer_id)`, `authenticated_identity(peer_id)`, and `owner_identity(room_id)`. These values must derive from authenticated host assignment state. Do not substitute a client-selected room, display name, door label, or profile lookup.

For every furnished room, pass the actual prop interaction anchors supplied by the world owner:

```gdscript
var mounted := DormStationMount.mount_room(dorm_interactions, room_id, {
	"kit_workshop": open_kit_anchor,
	"loadout": backpack_anchor,
	"notes": papers_anchor,
})
```

Keep `mounted` with the room instance and call `DormStationMount.unmount_room(...)` before freeing/reassigning it. Connect the provider assignment-change signal to `dorm_interactions.assignment_changed`; this closes a controller-opened personal panel when the local assignment/identity ceases to match.

The anchors receive concise contextual labels; this implementation creates no blue boxes, signs, duplicate profile stores, inventory copies, save writes, RPCs, or transaction paths. It delegates to the existing `electronics.open("kits"|"inventory"|"notes")` operations.

## Legacy shop fallback

After each mount/unmount/assignment update, iterate only legacy `shop_station` nodes and call:

```gdscript
DormShopFallbackPolicy.filter_legacy_station(dorm_interactions, station)
```

The policy hides/disables only pages `kits`, `inventory`, and `notes`, and only after the local authenticated owner's three replacement anchors are all mounted. `shop`, `ics`, `trade`, and `exit` remain enabled. If the room is incomplete, unmounted, or unassigned, legacy access remains/restores automatically. Re-run filtering after each lifecycle change so presentation matches the policy; interaction safety does not depend on presentation.

## Validation

Executed without starting Godot (the user is actively playing):

```powershell
& .\tests\campus\dorms\interactions\verify_source_contract.ps1
```

Result: PASS. `test_personal_station_router.gd` covers owner routes, visitor privacy, authenticated-identity mismatch, complete-mount gating, unrelated-shop preservation, assignment cleanup, and fallback restoration. It was authored but not executed because engine/runtime launches were prohibited. Runtime acceptance remains pending the user's later test session.

The referenced Library screenshots were not available through any supported Library materialization/inspection tool in this delegated thread, so no visual claim was inferred from their captions or IDs.
