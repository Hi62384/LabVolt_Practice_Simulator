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
