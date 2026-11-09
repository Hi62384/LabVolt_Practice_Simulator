# Design system delivery — API v1 ready

Implemented only in assigned exclusive directories:
- `scripts/ui/design_system/`: tokens, opt-in theme factory, shared text/action/header/card/field/badge/section/status/empty-state factories, existing-button migration helper, responsive collection grid, scrollable modal with focus traversal/restoration, additive review fixture script.
- `assets/ui/design_system/icons/`: 42 original SVGs with an explicit resource allowlist.
- `scenes/ui/design_system/review.tscn`: additive shop/layout/state fixture, absent from startup configuration.
- `tests/ui/design_system/`: bounded offline source/asset and consumer-symbol checks; deferred Godot contract test.
- `review_artifacts/ui_style_20261106/`: API, conventions, 55-source inventory, adoption matrix, source hashes/check reports and staged patches.

API readiness is final for version 1: existing published signatures will remain stable. Caller-owned IDs, component schemas, unit parsing, receipt state, host requests, save operations and mouse capture remain outside the design system. There is no project/global theme change. Theme variants expose normal/hover/pressed/disabled/focus, selected toggle/card, and input error states; factories retain visible labels and 44px minimum action height. Rarity is text plus color, including an actual tinted icon tile.

Validation completed offline:
- 65 source/asset checks passed; 42 valid bounded SVG assets; all owned resource paths resolve; no business/save/network APIs in the presentation layer.
- Text contrast checks: body 13.38:1, muted 8.65:1 on surface / 6.97:1 on raised, primary action 6.93:1, error text 8.21:1; disabled text 5.17:1. All six rarity text colors exceed 4.5:1 on raised surface.
- 42 concurrent source imports checked against real exported symbols, none missing. This is a const-preload symbol check, not a GDScript parser.
- Whole-file SHA-256 preimages retained for ten historical staged adoption targets. Nine have changed under their rightful owners and are explicitly marked `owner_changed_do_not_apply` in `source_checks.json`. Only `scripts/electronics_ui.gd` still matched at the final check; its isolated main-owned patch is `main_electronics_adoption.patch` / `.json`. Apply only after a fresh full SHA match and atomic dry-run; preserve its generation guard. Do not regenerate/reapply the old owner patches over their new redesigns.

Assigned substantive owners now cover every group in the adoption matrix. Main owns shared electronics/game/ledger/network/session integration. Shared API adoption is observed in hosting, avatar, academic, HUD/settings, instruments, editor and inventory source; this is not a claim that every screen is visually complete. Additional new owner helpers remain in their own directories.

Pending by playtest constraint: actual Godot GDScript parse/import, fixture render, keyboard/controller and narrow-window verification, live gameplay and multiplayer/receipt acceptance. No Godot/engine/server process was launched or controlled, no user save was mutated, and no active window was focused. The six supplied Library screenshot IDs had no supported direct-pixel route available in this task; no screenshot/image review is claimed. The implementation uses the explicit transcript and inspected source layouts.

Suggested later acceptance: open the additive fixture at 1280×720 and a narrow viewport, traverse focus/hover/disabled/error states, inspect rarity and field text; run `tests/ui/design_system/test_design_system.gd`; then each owner validates its actual reachable screen flows. Purchase acceptance must exercise the existing host/receipt API with temporary unlimited funds and stored balances unchanged.
