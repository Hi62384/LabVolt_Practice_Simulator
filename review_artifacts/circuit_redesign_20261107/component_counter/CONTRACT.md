# Component Counter integration contract

This private `store_panel.gd` replaces only the existing store panel after the recorded SHA-256 preimage matches. The source adapter still passes the real `profile.catalog()` (including owned variants), canonical rating `describe`/`quote`, and actual profile/ledger `buy` or `buy_configured` receipt path. `refresh_snapshot()` reads the profile snapshot and updates `$∞` or formatted dollars, ownership labels, and card counts without rebuilding the grid. No item or balance is fabricated.

Public helpers for the contextual picker: `Visual.icon(entry)` returns the existing SVG resource path, `Visual.family(entry)` returns the family label, and `Visual.rarity_color(rarity)` returns the shared design-token background. The picker should read ownership from the same profile inventory, not from this panel. Bundle/equipment and cosmetics owners can supply separate section controls to the surrounding store root; they should not alter this panel's component catalog or purchase action.

Sole integrator must route the `shop` page only from physical store M102 Component Counter, keep `trade` in M102, remove station nav tabs, and expose one compact store header with Close and the panel's currency display. Avoid a second title/balance in the electronics shell. The existing body scroll must not scroll the entire store; give the panel available height and let its internal component grid scroll.

The source filter now clears a stale saved search when it hides every product at open, aligns selection with visible cards after category/search changes, and shows an explicit empty state for a new no-result search. This assumes nonempty real catalog returned by `profile.catalog()`. If that source returns empty, the UI says unavailable and the integrator must fix the upstream source, not inject products.

No engine or GUI run was performed. Runtime owner should verify the candidate after integrator adoption at 1920×1080 and 1366×768, including M102 routing, catalog population, search, categories, variants, quantities, live card counts, receipts and pending/error states.
