# Legacy laboratory wear relocation candidate

Private candidate only. Copy `legacy_cosmetic_adapter.gd` to
`scripts/campus/facilities/clothing_store/` after reviewing the current preimages.

Exact four products from `ElectronicsProfile.COSMETICS`:

| ID | Price | Character setting effect |
|---|---:|---|
| `copper_coat` | 35 | outfit Lab coat; top e7eff0; accent c7804e |
| `gold_safety` | 25 | glasses Safety; accent e8bd55 |
| `blue_gloves` | 20 | gloves true; glove_color 426bd4 |
| `copper_hat` | 30 | hat Hard hat; hat_color c7804e |

These are legacy character appearance settings. Source search found no gameplay
hazard modifier keyed by these items; the visible character effect must be
retained. New avatar collectibles with similar names have different IDs,
prices and ownership; they cannot replace these products.

Store owner integration: add a compact `Laboratory wear` section in
`store_panel.gd`. Build cards from `LegacyCosmeticAdapter.rows(profile.data)`.
Show the returned real price and ownership. On Buy, generate the existing
request ID and send `purchase_request(id, request_id)` through the authenticated
`cosmetic` ledger operation, passing `args` exactly. Offline call the existing
`profile.buy_cosmetic(id)` and use its existing atomic save/rollback. Refresh
from the authoritative snapshot after acknowledgement. Never use the new
`cosmetic_purchase` avatar path or `owned_cosmetics` for these IDs.

On Wear, require `wear_settings(id, profile.data)` to return a nonempty map.
Require a selected character, read that character's existing `character.json`,
merge these settings, call `game.characters.save_character(selected, config)`,
and emit `game.characters.changed` on success. This is the exact current
electronics store Wear flow and preserves multiplayer appearance sharing.
Do not claim that `wear_settings` alone equips anything.

Only after the destination cards, Buy acknowledgement, Wear save and ownership
refresh are integrated, remove the legacy cosmetics block from the electronics
counter. Keep Analyzer, kit capacity, components, bundles and boxes there.

Preimages (SHA256, source read 2026-11-07):
`electronics_profile.gd` D676A708AE84EECB84833895A7B73545AD878354C9118D110AE9F5C9DE584563;
`electronics_ui.gd` 2AE602395705705A0E32C26C0226BEFE8539BCA6DA7A98010DD6FC1ABFBD62F0;
`campus_integration.gd` 9C37EF2A0AF23FCE67D5396C0928CD8D5CC17923C2405F5084D2B384494D1088;
`clothing_store/store_panel.gd` 3429C44147BE92455A2F351D3D47C8988DF451FC684ADCAC093B1F81DCFC19DF.
Re-read before applying any shared patch. No current production source changed.
