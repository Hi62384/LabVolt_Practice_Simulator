# Circuit builder integration handoff

Owned value search is implemented in `scripts/electronics/inventory_value_search/`. The query reads profile stock and `component_instances` without changing either. It calls the shared `component_values/values.gd` parser and descriptor API. The picker emits `(type_id, instance_id)` and keeps a selected real instance stable across refreshes, clearing it when the instance disappears.

The existing builder in `scripts/electronics_ui.gd` currently creates a `choice: OptionButton`, free-text name `search: LineEdit`, category and favorite filters in `breadboard()`. Replace only that component-choice section with `picker.gd`. Keep probe, wire, remove, interact and select tool entries as separate controls. On `picker.choice_changed`, set `canvas.selected_type` to the chosen type or `"select"` when it clears. Before `Board.validate(design, kit.items, ...)` in `canvas.design_changed`, call `picker.selection.bind_new_parts(design, kit.board)`. If it returns an error, restore the previous board as the current callback does on validation failure. This binds a specific selected instance in `design.instance_ids`; ordinary stock retains the existing type-only behavior. The host remains the authority on save, materialization, availability, and deployment.

Feed the picker with `picker.set_inventory(profile.data, profile.catalog(), reservations, kit.items)` on initial open and on each authoritative inventory snapshot. `reservations` is the existing `{counts, instance_ids}` availability projection; pass `{}` when no reservation applies. For creative/design modes, omit the `kit.items` limit, preserving their existing unrestricted design behavior. Refresh after a confirmed kit quantity change. No polling or new local ownership state is required.

Source tests: `tests/electronics/inventory_value_search/test_query.gd`. They call the production GDScript query and selection functions, including owned instances, generic stacks, SI targets, ties, reservations, refresh, and board binding. They have **not** been executed because the user is actively playtesting and engine launches are paused.

Shared-file preimage observed for this handoff: `scripts/electronics_ui.gd` SHA-256 `77A936A9392B875F128CAF345709E5145417A2C8111BC521B89B15460B28C705`. Recheck that hash or inspect the current hunk before applying the hook because the UI owner is editing this file.

Minimal save callback hook, inserted immediately before its current `var error: String=Board.validate(design,kit.items,creative or designing)` line:

```gdscript
var selection_error: String=picker.selection.bind_new_parts(design,kit.board)
if selection_error!="":canvas.board=kit.board.duplicate(true);canvas.queue_redraw();status.text=selection_error;return
```

The picker itself is instantiated once in `breadboard()` after `kit.board.definitions` and `canvas` are set, with `picker.set_inventory(profile.data,profile.catalog(),{},kit.items)` for ordinary kit building and `{}` in the fourth argument for creative/designing. Its `choice_changed` signal should set `canvas.selected_type` to the chosen type or `"select"` when selection clears, and clear `canvas.first`. Call `set_inventory` again on authoritative inventory refresh. Keep the existing canvas tool choices available alongside the picker; remove the old catalog-only component entries to avoid competing selections.
