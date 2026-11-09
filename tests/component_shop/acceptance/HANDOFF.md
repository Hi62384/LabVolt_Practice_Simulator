# Component shop production acceptance

Two runnable `SceneTree` suites exercise the integrated production scripts directly. Run serially from an isolated Godot test process when the runtime owner authorizes the engine window:

```
godot --headless --path . --script res://tests/component_shop/acceptance/test_purchase.gd
godot --headless --path . --script res://tests/component_shop/acceptance/test_search_and_queue.gd
```

Expected stdout markers: `ACCEPTANCE component_shop purchase PASS` and `ACCEPTANCE component_shop search/queue PASS`. Any assertion aborts with a specific failure label. Do not run either through the live game process. These suites were prepared without launching Godot; no runtime pass is claimed.

`test_purchase.gd` uses the production `InventoryAuthorityLedger.transact`, `ElectronicsProfile.buy_configured`, policy debit, catalog, receipts and profile validation. Its only substitution is an in-memory `persist` override so it cannot write a save. It covers arbitrary resistor ratings, 1000-item buying, unchanged playtest balance, legacy stock preservation, authenticated peer rejection, same-ID replay, changed-payload rejection, peer rebind, malformed quantities/values, spoofed price/rarity, commit failure and same-receipt retry.

`test_search_and_queue.gd` calls the actual `shop_services`, canonical values, `ShopState`, owned-value query and selection APIs. Synthetic inventory contains 800 Ω, 1 kΩ, and 1.2 kΩ. It checks SI normalization, legacy identity, quote stack bound, unsupported fields, nonfinite/negative/overflow values, nearest order, equal-distance order, empty stock, reservations, kit limits and pending-request correlation.

Scope: no scene rendering, network packet delivery, live profile, save file, server, CUA, visual appearance, or process restart is exercised. The UI transport callback is represented by `ShopState.begin_request/finish_request`; the full shop adapter signal and network queue still require isolated runtime/visual acceptance. No shared production or UI file was edited here.

Potential production issue to review after the suite runs: `inventory_value_search/query.gd::_closer` resolves exact distance ties with catalog traversal `ordinal`, rather than component ID. This is deterministic only if catalog insertion order is stable. The minimal fix is to compare `type` then `instance_id` after `distance`, if the product requirement is order independent of catalog construction. The acceptance fixture currently expects the production catalog order.

## Failed guarded run diagnosis and correction

The first guarded run receipts are preserved at `C:/Users/User1/AppData/Local/Temp/labvolt-parser-five-39322d559ed2461badf240489eb8603b/shop_purchase-evidence` and `.../shop_search-evidence`. Both logged `WARNING: Exponent too high` after the deliberate `1e999` hostile rating reached `String.to_float()` in `values.gd::parse`. The parser now checks decimal magnitude before conversion and returns the existing range error without invoking float conversion. The search test's `900 Ω` expectation was wrong: 800 Ω and 1 kΩ are both 100 Ω away, and production tie order puts the existing catalog 1 kΩ row first. The ranking-change test now uses 850 Ω, where 800 Ω is strictly closer. The separate 1 kΩ tie test remains intact.

The first fixtures used `assert` inside `check`, which logged an assertion yet continued to print PASS. Both suites now count failures and emit only a FAIL marker with `quit(1)` when any check fails. No Godot rerun was performed by this task. The runtime owner should rerun both suites in isolation and treat either a nonzero exit, `FAIL` marker, `WARNING`, or `SCRIPT ERROR` as failure, even if a PASS marker appears in older receipts.
