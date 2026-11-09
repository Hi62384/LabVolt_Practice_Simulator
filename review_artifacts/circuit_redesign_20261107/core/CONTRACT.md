# Circuit workspace contract

Proposed install namespace: `res://scripts/electronics/circuit_workspace/`.
Workspace owns a real breadboard_canvas subclass, not a second electrical model.
`configure(board: Dictionary, actions: Dictionary)` receives a duplicate editable board and explicit host Callables: save, deploy, recall, carry, close. Host retains inventory validation, bind_new_parts, profile saves and authority requests. `design_changed(board)` forwards candidate edits to that existing validator; rejection must restore accepted board. No optimistic deploy state.
Signals: `panel_requested(kind: String)` for component picker, analyzer, bench mappings, projects; `selection_changed(ids: Array)` for inspector; legacy `code_requested` and `io_command_requested` remain on canvas and must be connected with wire_io_canvas.
Panels call `choose_component(type_id)`, access `canvas` for existing analyzer/capture interfaces, and close independently. No global navigation. Component picker uses the existing inventory selection/bind_new_parts service. Buying and trading remain in the store.
Canvas owns zoom/pan, tool selection and keyboard gestures; model, inventory and solver stay existing services. Entry must replace the entire breadboard page scroll with an expanding workspace, not append it inside the old form.
Runtime acceptance belongs to runtime owner: actual 1920×1080 and 1366×768 screenshots remain required. No engine execution by this owner.

## Implemented integration extension

`host_adapter.gd` now mounts contextual `panel_host.gd` under the canvas as a true overlay, supplies all panel_data/panel_actions callbacks, and retains itself in workspace metadata from the staged breadboard entry. Do not apply contextual owner's older CORE_WORKSPACE_MOUNT.patch as well: this adapter already performs that mount. Install the contextual owner modules alongside this packet before applying source candidates.

`component_selected(type_id)` clears previous measured-instance binding before the picker records a new instance. `record_instance` refreshes canonical Query rows against actual profile/kit stock and calls existing Selection.choose. Property submissions go through Values.resolve/configure and replace the canonical type ID; owned quantity validation remains mandatory. This does not invent a mutable resistance field that the solver ignores. An unavailable value is rejected rather than deployed. Ports use Board.node and the same guarded save transaction. Failed validation/save restores the accepted board and undo/redo histories. Live save/deploy is never called by private source checks.

Canvas keeps original drawing, electrical terminals, controls, probes and model transformations through inheritance. Ghost placement and movement are presentation only until validated commit. Faint rings mean unoccupied holes, not a promise that an entire package fits; the full hovered mounting geometry is checked by Board.validate and turns red on rejection. R rotates pending geometry. Default two-anchor workflow and repeated placement remain. Wire selection supports whole-wire highlight, copy/paste, delete and endpoint context menu. Component context supports rotate/copy/duplicate/delete/fit. Grid snapping is always to real mounting holes.

Project popup exposes saved projects, carry, reset view and supported board row counts. Existing saved projects open through the current kits page; correct IC/PCB project routing remains with the dedicated editor owner. Existing code_requested and io_command_requested are connected by host.wire_io_canvas. Workspace refreshes the contextual analyzer from actual solver-produced canvas data; it introduces no solver loop.
