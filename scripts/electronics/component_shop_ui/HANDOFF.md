# Component store handoff

Implemented only in assigned component_shop_ui script/asset/test directories.
No Godot/editor/server/process, CUA, reload, or user-save action was performed.
No screenshot pixels were available through the supported route, so this work
is grounded in source and the explicit text requirements, not claimed image review.

## Integration owned by main

`shared_hookups.json` contains exact unique preimages and SHA-256 hashes for the
current shared electronics UI and authority network. They are staged, not applied.
Apply only when each preimage still matches, otherwise reconcile deliberately.
It adds a persistent `component_shop` adapter, replaces the shop with the actual
store panel, preserves existing analyzer/boxes/accessories/capacity actions behind
"More supplies & upgrades", removes station tabs only inside the shop, removes
the duplicate stored-money header inside shop, and wires host submission/result
correlation. Other station pages retain their existing routes.

The canonical rating owner has now supplied `component_values/shop_services.gd`.
The adapter consumes its **actual describe/quote API by default**, including its
`buy_configured` intent. It calls the integrator-owned
`profile.buy_configured(base_id, settings, quantity)` when available. The profile,
ledger and validation integration of that operation is still the main/rating
owner's responsibility. An unavailable method produces an explicit error; no
fake cart or local inventory write is used. Existing custom IC IDs use the real
legacy `profile.buy` and retain its 100-unit limit.

`component_shop_services()` in the staged hook returns `{}` until integration
supplies `{ "economy": authenticated_host_policy_snapshot }`. This must come
from the existing policy's host display snapshot; never set an unlimited client
flag or edit stored dollars. Optional service overrides are `theme`, `describe`,
`quote`, `snapshot` (panel API), and `submit` (adapter API). The shared design
system Theme/Tokens are the default; local icons extend it with original
potentiometer/transistor/power/board/display/speaker glyphs.

Network ordering matters: call `component_shop.submitted(request_id, op)` after
enqueue and **before flush**. A host can answer synchronously. Call
`component_shop.received(request_id, result)` only after successful authority
accept/save, or on a real host rejection. A local save failure must keep the
request pending. Do not use inventory deltas, optimistic success, or timeouts to
declare success. The staged patch retains the existing queue and receipt retry.
Shop snapshots refresh ownership without rebuilding fields or clearing results.

An optional canonical `submit(local_id, intent, completion)` adapter must route
through the authenticated receipt-backed queue and call completion with the
same local_id only on final accepted/rejected result. It must preserve retries
under the same host transaction ID and notify rejection if queueing fails.

The panel locks repeat purchases while pending, ignores stale responses,
invalidates confirmation on every field edit, permits SI-unit text through the
canonical service, validates quantity with `Values.quantity`, and displays both
rarity text and rarity-colored icons. Product search matches family/name/rating/
rarity. Lists follow focus and switch to a stacked layout below 850 pixels.

## Verification and remaining acceptance

Run the bounded offline checker:
`python tests/electronics/component_shop_ui/check_source.py`.
It verifies original SVGs, resource references, no direct shop persistence/RPC
writes and unique staged preimages. It is not a GDScript parser or runtime test.

`test_store_panel.gd` is authored for later isolated engine testing and has NOT
been run during active playtesting. It exercises quantity rejection, review
invalidation, exact opaque intent preservation, duplicate-click locking, stale
response rejection and host-error recovery without touching profile saves.

Later runtime acceptance must cover: GDScript parse; 1280×720 and narrow/high-DPI
layouts; screen reader names; keyboard/controller focus through the scroll list;
long model names/ratings; configurable resistor/capacitor/inductor/semiconductor
units and bounds; quantities and stack limits; repeated confirms; host rejection;
client/host synchronous and asynchronous receipts; disconnect/reconnect during
commit; local-save failure retry; extra shop actions; profile switching; stored
balance preservation and authenticated Unlimited display. No visual/runtime
acceptance is claimed by this delivery.

## Later components-counter reconciliation (UNVERIFIED)

The original store/counter/kit-builder request and its later corrections are implemented through the Electronics Store's Components, Bundles and Store sections; the Components Counter's My Components and Kit Builder sections; four priced kit tiers; lab goggles sold with electronics equipment; loose stock shown after kit reservations; and inter-bench external leads. Source review found a second Circuit Studio kit-library target that always failed the workshop-only builder check. That unusable target and its manifest route were removed; the Components Counter in the Electronics Workshop remains the kit-builder entrance.

Kit component quantity changes and kit deletion now use dedicated host transactions. The host requires Components Counter proximity, checks the kit and catalog entry, and rejects changes while that kit's board is deployed. Existing-kit item counts and removals are no longer accepted through a replacement metadata document. Buying a kit requires Electronics Store proximity; copying or deleting one requires Components Counter proximity. The client also gives an immediate placed-board notice when it can observe the condition. Inventory is still represented by master stock and reserved kit counts, so loose stock excludes components packed into kits without a destructive rewrite of saved inventory. All of these later source changes are UNVERIFIED: the user instructed no tests or startup smoke test.

The later screenshot correction was about a plant intersecting the Electronics Store table. The workshop décor no longer mounts that plant at the counter; the separate far-corner plant remains. Visual placement is UNVERIFIED.

The copied-kit path now places a successfully copied kit into a real hotbar, equipped backpack or dorm-cabinet slot using the same destination policy as a purchased kit. Previously it created a profile-only kit that the carried-kit grid could not show. A failed placement restores the prior profile, and the host ledger still checks reserved component stock before committing the copy. This is UNVERIFIED source work; it did not change any player's actual save.

The active maker canvas already provides validated wire-end and component-pin grabs in all editor modes, including two-pin reconnection, footprint movement, undo, and host-side candidate validation. Its right-click path now removes a clicked part or jumper even when the first placement hole was pending. Board replacement, import, save rollback and accepted external edits clear pending grabs, drags and lab-lead selection. This source reconciliation is UNVERIFIED; no engine or UI checks were run.

The next original request asked for rails on both sides. The current board model already has P/N above and W/X below the standard rows; the canvas and physical socket mesh both iterate those letters. The later toolbar shape, thin wire swatch and icon requests are represented by the maker workspace toolbar. The subsequent report about hard-to-click holes had a concrete source gap: the regular breadboard hit test accepted points only nine grid units from a hole. It now accepts points within 11.25 units, just under half the 23-unit pitch; standalone PCB pad hit testing keeps its existing radius. This remains UNVERIFIED visual and interaction work.

A later kit interaction correction asked that clicking an open kit while holding its breadboard return the board and close the kit, with a follow-up allowing left click too. Both click paths already sent `return_held_board`, but the host left `kit.open` true after a successful recall. The host now closes it only after `_recall_board` succeeds. The pickup guard still requires the board returned and kit closed. This is UNVERIFIED.
