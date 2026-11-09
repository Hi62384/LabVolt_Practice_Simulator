# Component values handoff

Implemented only in the assigned new directories. No shared gameplay source was modified by this task. No engine, server, renderer, CUA, reload, active save, actual purchase, process control, network download or screenshot review was performed. No applicable AGENTS.md was found in the repository or its ancestors. Work is grounded in the explicit feature requirements and inspected model source.

## Delivered

- `scripts/electronics/component_values/values.gd`: canonical SI parser/formatter, supported parameter schema, deterministic family identities, legacy-match retention, reversible validated procedural IDs, catalog augmentation, positive integer quantity and bounded pure purchase plans.
- `scripts/electronics/component_values/shop_services.gd`: existing shop describe/quote callback contract. No duplicated unit parser or client-trusted price.
- `tests/electronics/component_values/offline_checks.py`: eight passing source/data checks (including worker numeric-field coverage and exact integration preimages). Decimal checks use an independent oracle and do not execute the production GDScript parser.
- `tests/electronics/component_values/test_values.gd`: deferred production parser/value/quantity/identity fixtures.
- `tests/electronics/component_values/test_authority.gd`: deferred in-memory ledger fixtures for unbound peers, replay/changed-receipt rejection, peer rebind, host validation, unlimited debit, malformed profile identity and failed-commit rollback/retry. It overrides ledger persistence and never opens files; it still needs Godot and the shared patch, so it was not run.

## Shared integration remains staged

`shared_patch.json` contains 19 exact preimage-bound edit blocks across eight files; `shared_integration.patch` is the review diff. Full-file original SHA256 values are recorded for comparison. The staging generator only writes artifacts in this directory, never shared files. Re-run generation only after inspecting current partial integration: it intentionally fails closed if a preimage changed or was already applied. Do not blindly regenerate or reapply after another owner starts integration.

The exact edits cover:

1. `electronics_catalog.gd`: reconstruct validated procedural entries for simulation; retain immutable per-entry caching with a 512-entry bound.
2. `electronics_profile.gd`: validate/resolve owned procedural stock, expose it through profile catalog, and add `buy_configured` with host guard, policy debit, stack/cost checks and save rollback. Missing crafting-material messages resolve procedural names.
3. `inventory_authority/ledger.gd`: receipt-backed `buy_configured` dispatch/success checks and procedural stock recognition in trade offers. Existing digest/replay/persist/account binding remains authoritative.
4. `breadboard_model.gd`, `custom_circuit.gd`, `physical_resistors.gd`: resolve configured items in board validation, expansion, nested crafting, material pricing and persistent physical resistor manufacturing.
5. `electronics_ui.gd`, `dc_lab.gd`: resolve procedural material labels and device kinds rather than directly indexing fixed built-ins.

The separate shop owner has already independently connected `shop_services.gd`, `buy_configured` submission/receipt matching, six-digit quantity input and canonical quantity validation. These were observed in source; this task did not edit their files. Their custom IC purchase path retains its legacy separate per-buy bound. Main integrator still owns final shop/network/policy snapshot wiring.

Optional remaining display follow-up for the relevant owner: `campus_social.gd::_source` uses the fixed cached catalog and falls back to raw IDs when describing procedural stock. Its counts and ownership remain correct; use `Values.augment(catalog_cache,inventory.keys())` there for readable names. This is outside the assigned component source scope and is not patched.

## Verification and limits

Ran `python tests/electronics/component_values/stage_integration.py` and `python tests/electronics/component_values/offline_checks.py`: 19 edits staged, eight source/data checks passed. A Windows default-codepage issue in the check was corrected by explicitly reading UTF-8. A proposed shop patch preimage failed because the shop owner had already implemented that integration; it was discarded without any shared mutation.

No Godot/GDScript parse, visual or runtime acceptance is claimed. Once the user authorizes an engine test window, run both deferred GDScript fixtures after applying the shared integration and review real shop/board behavior. Current policy changes debit only: stored dollars remain finite and unchanged. Representation/model bounds are explicit in `CONTRACT.md`; wattage for physical resistors changes overrating indication, not an invented damage model. Prose-only capacitor voltage ratings and hardcoded behavior remain informational.

Legacy components and save IDs are never migrated or merged. Equivalent new requests share canonical identity; a matching legacy catalog ID is reused for new purchases. Existing explicit legacy IDs always resolve unchanged.
