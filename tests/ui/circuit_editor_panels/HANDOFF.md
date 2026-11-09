# Circuit editor interface adoption

Implemented in the five exclusively assigned files, using actual `design_system/widgets.gd` and `theme.gd` primitives through the presentation-only `scripts/ui/circuit_editor_panels/chrome.gd` adapter. No second token/icon/widget system, external asset, dependency or station switcher was introduced.

| File | Concrete layout changes |
| --- | --- |
| `scripts/firmware_ide.gd` | Target and deployment card, wrapping icon action rows, labeled search/replacement/filename/template controls, source editor and validation/serial cards, optional language/wiring reference. Source minimum width reduced from 850 to 280 so existing parent scrolling can accommodate smaller windows. |
| `scripts/firmware_backends/native_studio.gd` | Local native target heading, labeled board picker, shared scoped theme and focus sizing. Device selection/save/upload/control authority functions unchanged. |
| `scripts/firmware_backends/native_ide.gd` | Source workspace, compiler diagnostics, compiled image/deployment, debug/serial cards; shared icon actions and labeled compact fields; 320 px source editor; optional compatibility guide and board pin reference card. Existing source tabs/editor identities retained. |
| `scripts/package_editor/package_form.gd` | Body/identity, surface controls and external pin sections; labeled metadata, connector, role and physical dimensions; individual pin cards and explicit reorder buttons; local package-save result. Original package-store result still emitted to caller. |
| `scripts/pcb_design/editor.gd` | Workflow, mode-specific outline/copper cards, board dimensions and feedback cards; icon actions and labeled selectors. Mode visibility follows existing mode callback. Canvas, coordinate system, route gestures, semantic colors, snapping values and document operations unchanged. |

## Integration

No new shared entry hook is required. Existing `electronics_ui.gd` already constructs firmware in its code page, the package form in the package builder, and PCB editor in `open_pcb_routing`. Native firmware still enters through firmware_ide -> native_studio -> native_ide. These shared files were read only; no staged main-file mutation is necessary for this adoption. Existing outer ScrollContainer remains responsible for viewport scrolling. Physical IC/PCB station routing remains with its dedicated owner.

No game, save, session, network, privacy, catalog, simulation, source compiler, route canvas, or world file was edited. No executable, build, engine, server, UI focus, reload, screenshot or active-save operation was invoked. `git status` reported that this directory has no Git repository; exact source preimages are retained here instead.

## Offline evidence and reversibility

`manifest.json` records all five before/after SHA-256 pairs. `preimages/` retains exact original bytes. `verify_source.py` checks these hashes, 43 unchanged behavior methods, protected build/save/runtime statements, referenced resource existence, balanced source delimiters, source-tab indices and pin-row indices. Run from repository root with `python tests/ui/circuit_editor_panels/verify_source.py`; the latest result is in `validation.txt`.

`adopt.py`, `refine.py` and `finish.py` are completed one-shot source migrations, retained as review evidence; do not rerun against adopted sources. `rollback.py` restores only these five exact preimages and refuses to overwrite unknown source revisions. It has not been executed. New helper and review files are left intact by rollback.

These are source-contract checks, not a GDScript parse or behavioral/visual acceptance. No standalone GDScript parser was installed in the environment, and Godot execution is prohibited during the active playtest. Runtime acceptance remains at a safe user boundary: check small/wide window layout, keyboard focus traversal, native board selection, firmware draft restore and tabs, compiler diagnostics/navigation/upload, serial/breakpoints, 1/64 pin visibility and reorder/save results, PCB mode switching, outline/routing gestures, undo/redo, dimensions and saved-copy signal feedback.
