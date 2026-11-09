# Avatar cosmetic customizer integration handoff

## Studio design and host callbacks

The panel consumes the actual `scripts/ui/design_system/theme.gd.create()` and `tokens.gd.card_style()/rarity_color()` API. Category marks, shared rarity rails, Worn/Owned labels, selection styling, scrollable parameters with numeric feedback, Apply, Revert, and discard confirmation are implemented in the owned UI.

Main must connect `panel.apply_requested(intent)` to the authoritative edit transaction and call `panel.acknowledge_apply(ok, message)` with the result. Existing `EditorHost` currently connects only draft/close/animation; therefore the new Apply button requires this explicit host connection. Preserve the one-transaction `edit` payload; do not call the old full-state `request_apply()` as if it accepted that payload. Revert emits one `draft_changed` update. Parameter gestures keep their widgets alive and update the preview without rebuilding the controls.

## Body rendering audit (current actual avatar_renderer.gd)

All 20 fields persist through core sanitization and the persistence body/edit intent. Twelve currently reach Toon.build through explicit renderer mappings: height, width→build, head, head_width→face_width, head_height→face_height, shoulders, waist, arm_length, hands→hand_size, leg_length, feet→shoe_size, skin.

Eight have no current renderer mapping: neck_length, neck_width, torso_length, torso_width, hips, arm_width, leg_width, and build (slim/average/heavy/muscular). Main must implement these in the character/renderer and clothing/accessory fitting before claiming they visibly work. The build enum must not overwrite the numeric width→legacy build mapping; apply named build as a separate bounded silhouette factor. Neck changes must move the head and its attachments, torso length must move arm/head anchors, and arm/leg thickness must preserve animated limb nodes and item attachment transforms. Controls remain present to preserve the requested interface and stored data; no visual acceptance is claimed.

This additive layer does not replace `toon_editor.gd`, menus, profile, network, store, or footwear/core files. It follows the shared v1 contract in `C:/Users/User1/Documents/Codex/2026-11-03/bas/work/avatar_collectibles_v1/CONTRACT.md`.

## Mounting

1. Primary creator integration is the real `scripts/avatar_cosmetics/core/editor_host.gd`, not a second hand-built panel binding. Mount an `EditorHost`, call `open_profile(profile.data, legacy_character)`, connect `apply_requested(state)`, and call `request_apply()` only from the existing Apply/Save action. `open_profile` already creates the panel, shared cache/renderer, `AvatarRenderer.render_avatar` binding, draft coordinator, and idle/walk route.
2. The exact panel API used by the host is `panel.configure(catalog, owned, draft, cache, AvatarRenderer.render_avatar, AvatarCore.resolve)`. This signature has been verified against the current host and renderer.
3. `AvatarCosmeticUIBinding` remains a read-only convenience for later store/other surfaces that already have a catalog and resolved v1 profile. It must not replace `EditorHost` in the creator because the host owns legacy migration/coordinator state.
4. Treat `equipment_intent_requested` as a validated staged intent, not an instruction to save on every slider tick. `draft_changed` is preview state only.
5. On Apply, use `panel.atomic_edit_intent()`, whose exact persistence shape is `{op:"edit", changes:[{op:"body",body:{...}}, {op:"unequip",slot:"..."}, {op:"equip",id:"...",parameters:{...}}]}`. Do not submit when `panel.is_dirty()` is false or `changes` is empty. The builder emits only changed body/equipment entries and replaces an occupied slot with one `equip`, not an unnecessary `unequip`+`equip` pair.

## Store reuse

`CosmeticItemCard`, `CosmeticItemGrid`, and `CosmeticThumbnailCache` are deliberately context-neutral. The store can bind catalog definitions to the same card/grid and add price/ownership labels around the card without creating live per-item viewports. Store preview drafts must remain separate from purchases.

## Contract seams

- `catalog_adapter.gd` consumes the contract fields without defining a second catalog schema.
- Item parameters come exclusively from `definition.parameters`; unknown widget types are omitted.
- The injected `AvatarCore.resolve` is authoritative for ownership/conflicts/sanitization.
- The injected `AvatarRenderer.render_avatar` is authoritative for character construction.
- Static `definition.thumbnail` wins. Missing static thumbnails are queued and rendered one at a time by the shared renderer; the in-memory LRU is bounded (default 160).
- The renderer output is currently memory-cached for the session. If disk persistence is desired, the integrator may add `user://cosmetic_thumbnails/v1/<key>.png` behind the cache without changing cards.
- The body UI schema is derived from `AvatarCore.BODY_FIELDS`, `BODY_MIN`, and `BODY_MAX`; it has no independent range constants. Current legitimate legacy values from 0.65 through 1.4 therefore remain unchanged when the editor opens.
- Persistence now accepts the atomic `edit` shape above, plus individual `body`, `unequip`, and `equip` operations. The previous snapshot note is superseded. Main should change `EditorHost.request_apply()` to emit/use `panel.atomic_edit_intent()` (or expose it beside the resolved state) and let the authoritative adapter apply that one transaction.
- Current `EditorHost`/`Coordinator.begin_preview()` resolves equipment into a state that does not carry `legacy_character`, while `AvatarRenderer` looks for `state.legacy_character`. Main must reconcile that render-only legacy base before integration; opening and saving an untouched legacy character must not replace its appearance with defaults. The UI's `is_dirty()` guard prevents a no-op editor visit from becoming a save, but it cannot repair the host's preview base from inside this owned directory.
- The grid builds cards in deferred batches of 24. Refresh/exit invalidates old generations and releases thumbnail references, so abandoned jobs are removed unless another grid/store still references the same cache key.

## Validation

The source-level suite is `res://scripts/avatar_cosmetics/ui/tests/test_ui_contract.gd`. It covers category/schema filtering, stable cache keys, selection/unequip, and manual camera ownership. Run it later with the project's Godot binary using `--headless --path <project> --script res://scripts/avatar_cosmetics/ui/tests/test_ui_contract.gd`; it was intentionally not executed during the user's active play session.

The placeholder SVG is a development fallback only. No visual acceptance is claimed; final spacing, controller navigation, thumbnail framing, and avatar fit need an authorized visual pass after the play session.
