# Dorm customization handoff

This packet only owns `customization/`. Copy its `scripts/campus/dorms/customization/*.gd` into matching project paths, and its test into `tests/campus/dorms/`. No production preimage is modified in this packet. Integration must resolve any conflicts against the current adopted authority and furnished room before copying.

## Host mount

Instantiate `DormEditService` in the integrated host dorm coordinator. Bind its six callables to the **adopted** persistent authority, room store, and master inventory catalog. The sender for RPC requests must be `multiplayer.get_remote_sender_id()`; do not read a peer or identity from request payload. Only the host calls `edit_for_peer(peer, logical_room_id, expected_revision, intent)`. The room store's `commit_room` must compare the expected revision and save atomically with the existing ledger, preserving other room/profile fields. Failure leaves state untouched. Reply with `{ok, error?, state, revision}`. Broadcast the new public room projection to visitors only after successful commit.

The `eligible` callback must verify a placed ID resolves to an actually owned item in the existing catalog, or to a default fixed furnishing listed in `ROOM_CONTRACT.md`. It must check the same item ID is not placed twice or reserved elsewhere, enforce surface attachment for `display`, `desk_laptop`, and lamps, and ensure a display definition is public and lightweight. Style variants beyond defaults require an actual unlock/store entitlement. Pickup removes the placement record only; it must not credit duplicate inventory. The callback receives the authenticated stable identity, candidate intent, and proposed customization. The edit service checks room ownership separately.

Physical bay side comes from the active hallway entrance's room contract. For an instanced logical room, use the instanced interior's own side. `DormPlacementRules` validates the full footprint, door sweep, reserved 1.5 m entry path, overlap and avatar navigation. Add fixed furniture footprints to `items` before validation or pass them as immutable occupied geometry when integrating the furnished room. Wall posters and tabletop objects still need the catalog adapter's attachment test.

## Client mount

Create `DormDecoratePanel` only for the local authenticated owner while their room is streamed. Call `open_room(saved.customization, host_derived_owned_options, side, submit_callable)`. The callable sends `intent` plus the current room revision through the adopted dorm RPC and returns `{}` while pending; call `accept_result(host_reply)` when the reply arrives. For local host calls it may return the result directly. Connect `preview_changed` to one translucent local-only ghost mesh, never to the authoritative room scene. Render the accepted state after replies; on rejection, the panel clears the ghost and restores the authoritative snapshot. Close and free the panel on room exit, owner change or disconnect. The panel has no permanent HUD surface.

Mount a small contextual "Decorate" interaction in the furnished owner's room and use the existing interaction routing. Its visual option list comes from the real owned inventory and catalog; the panel never invents ownership. Styles and placement actions are owner-only, including while a visitor shares the interior. The host must filter private files and stored contents out of visitor room projections.

## Verification limits

`tests/campus/dorms/test_customization.gd` is a synthetic unit fixture to run after mounting, for example with the project's normal Godot test command. It has not run in this packet because the delegated scope prohibits engine execution. The integration owner still needs live checks for actual item catalog eligibility, room render and collision, saved reload, multiplayer visitor rejection, and screenshots. Static source here does not establish the user's missing assignment bug is fixed.
