# Harbor Outfitters integration handoff

## Current adoption correction — 2026-11-06

`store_panel.gd` now adopts the real shared `Skin.create()` and `UI.action` /
`UI.badge` APIs, existing parameter panel, and `Renderer.render_avatar`.
`open_profile(snapshot, optional_avatar, authoritative_economy_display)` consumes
the **separate** `Policy.display_snapshot(true)` result, whose keys are `ok` and
`unlimited_purchases`. Do not put policy flags into profile data or accept them
from a client. The old `purchasing_power_unlimited` profile flag is obsolete.

The panel renders the selected item with hypothetical ownership only in a
disposable renderer state. Cancel restores the authoritative equipment. All 41
definitions and their parameter schemas remain available. Existing item cards
provide rarity/selection/focus; the detail area shows price and ownership.
Buy opens a confirmation dialog; Owned exposes Equip. Pending disables both.
Equip emits `avatar_cosmetic` with `{op:"equip", id, parameters}` through the
same `session.purchase_requested` transport signal. Purchase emits
`cosmetic_purchase` with `{op:"purchase", id}`. Transport must call existing
`ledger.transact(authenticated_peer, request_id, request.op, [request.intent])`.
The shared ledger already supports both operation names. Do not install the
older suggested duplicate match branch below.

**Shared policy correction still required:** observed
`scripts/avatar_cosmetics/persistence/profile_adapter.gd` SHA256
`1FF0BDB9EBE3C296C8D3098628FB79FF69C4EB210CCB718B3BBFACDCFE29147A`
still uses `if int(balance) < int(price)` and subtracts price directly. In its
purchase branch, after the existing duplicate/price/balance checks, call
`Policy.purchase_debit(int(balance), int(price), true)`, return failure on
`not debit.ok`, and assign `purchased.dollars = debit.next_balance`. Preserve
the ownership append and the existing ledger single receipt/persist operation.
Observed ledger SHA256:
`2FE9E93D9CA35A7C7F47894B8E3B41850315F19E696E6B7F620F9ED6EE64976D`.
Recheck these preimages before changing shared files.

Room checkout anchor is now `[4.9,0,4.45]`, outside the counter footprint.
Runner ends at z=7.4 inside the doorway. Hanging clothing uses authored tapered
silhouettes instead of boxes. Central door route stays clear between x=-1.35
and x=1.35 from z=0 through entry; the bench is west of the route. Geometry
remains procedural source and has not been rendered or collision-tested.

This module is additive. It does not edit the shared room registry, ledger,
profile, avatar UI, or main scene.

## World hook

Instantiate `room_builder.gd` under the campus world at the world origin chosen
for the separate store. Call `registry_record(global_position)` and merge that
record into the shared room/directory source. The record publishes world-space
bounds, door, catalog, mirror and checkout anchors. The builder's local AABB is
`(-9, 0, -8)` through `(9, 4.2, 8)`; choose an origin whose translated bounds
do not overlap an existing room. Keep the component shop unchanged.

## UI and avatar preview hook

Create one `store_session.gd` while the player is in range. Feed `open()` only
the authenticated profile snapshot. Bind browse/filter views to
`store_catalog.gd`; it consumes the four existing cosmetic catalogs and exposes
their real prices and supported parameters. Existing `CosmeticItemGrid`,
`CosmeticItemCard`, `CosmeticThumbnailCache`, parameter panel and live preview
can consume each returned definition without a second schema.

On `preview_changed`, render the supplied item/parameters on a disposable local
avatar preview. Do not persist or replicate `preview_only`. On
`preview_cancelled`, restore the avatar from the last authoritative snapshot.
Instance-local avatar materials remain the renderer's responsibility; this
module never mutates shared imported resources.

## Exact shared ledger seam

In `scripts/inventory_authority/ledger.gd::transact`, after the existing line
`var p=Profile.new();p.data=a.profile.duplicate(true)` and inside `match op`, add
a `cosmetic_purchase` case that accepts exactly one intent dictionary. Construct
one `ClothingStoreLedgerBridge`, then:

```gdscript
"cosmetic_purchase":
    if args.size()!=1 or not args[0] is Dictionary:
        return failure("Invalid cosmetic purchase")
    var result := clothing_store_bridge.apply_to_transaction_profile(p.data, {
        "op": "cosmetic_purchase", "intent": args[0]
    })
    if not result.ok:
        return failure(result.error)
    p.data = result.profile
```

Add `cosmetic_purchase` to the existing success-required operation list only if
the ledger sets an equivalent success flag for this branch. Preserve the
existing authenticated peer binding, request digest/receipt replay check,
transaction-local profile copy, profile validation, single `next` copy,
revision increment and final `persist(next)`. Do not call `commit_local()`.

The separate authoritative playtest purchasing-power policy may allow this
operation without decrementing stored dollars. Apply that policy in the shared
ledger/profile transaction before commit and expose only the boolean
`unlimited_purchases` in a separate policy display snapshot. Prices remain catalog-derived and
visible. The store must never synthesize balance, and ownership/duplicate
checks remain authoritative.

Forward the receipt result and fresh authoritative snapshot to
`accept_authoritative_result()`. A repeated request ID is handled by the
ledger's existing receipt journal; a different request ID for an owned item is
rejected by `profile_adapter.gd` before a debit.
