# Paper workspace component contract

Workspace owns document rendering, page navigation, zoom/pan, annotations, privacy, answer requests and save lifecycle in `scripts/paper_ui.gd`.

Calculator owner supplies `res://scripts/ui/paper_workspace/calculator/drawer.gd` extending Control. `configure(calculator: Control)` adopts the existing `scientific_calculator.gd` instance and preserves its public `display`, `degrees`, `answer`, `memory`, `result`, `mode`, `memory_label`. Drawer handles peek, hover reveal, pin/drag/unpin transition. Workspace positions drawer at right edge and may hide it when math policy disables calculator. No game/session calls.

Tool owner supplies `res://scripts/ui/paper_workspace/tools/case.gd` extending Control. Signals: `tool_selected(tool: String)`, `properties_changed(properties: Dictionary)`, `text_action(action: String)`. `configure(initial_tool: String, properties: Dictionary)`; `set_selection(item: Dictionary)` for selected annotation; `set_tool(tool: String)` optional. Tool values are `answer`, `pencil`, `eraser`, `text`; text equation mode is property `equation: bool`, not a fourth tool. Case handles peek/reveal/selection lock and visual cursor hint. Properties include `color`, `width`, `hardness`, `opacity`, text `font`, `font_size`, `angle`. Workspace maps equation mode to legacy annotation kind `equation` and sends existing annotation requests. `text_action("bake")` marks selected text baked through `update_selected` so original text remains visible. No direct data mutation by component.

These are stable source paths; workspace must guard ResourceLoader availability until components land. No live save migration.
