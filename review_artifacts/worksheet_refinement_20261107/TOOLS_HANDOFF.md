# Pencil case source handoff

Owner files: `scripts/ui/paper_workspace/tools/case.gd`, `body.gd`, cursor SVGs under `assets/ui/paper_workspace/tools`.

The case now draws a fabric body, zipper track and teeth, recessed compartments, a pencil, eraser, and text stamp as one lightweight 2D Control. Three transparent hit targets map to those silhouettes. It retains `configure`, `set_tool`, `set_selection`, `tool_selected`, `properties_changed`, `text_action`, and `cursor_texture` so the adopted workspace can instantiate it. The existing right-edge anchor at x = viewport width - 292 remains the fixed dock. A selected tool locks it open; deselecting it permits the 42 px peek when hover leaves. The object has no drag path.

Required owner integration before claiming complete functionality:

1. In `paper_ui.gd`, `_case_properties_changed` currently clamps pencil width to 8 despite the case exposing 1–32. Either support the full range or tell the case its actual limit. The ink eraser uses a fixed 12 px hit radius and ignores case size/hardness. Route contextual eraser settings to ink. Store stroke opacity/hardness and pressure in the existing stroke request and model.
2. `paper_ui.gd` currently applies a global custom cursor, including while over other controls. Apply `cursor_texture(tool)` only to the paper input area and clear it on close, page rebuild, and tool deselect.
3. `paper_annotations.gd` selects existing unbaked text and uses normalized page positions. It currently deletes text when the eraser touches it. Remove that eraser behavior for live text. Its new-text path uses defaults for font/size/angle/mode, but new objects still need multiline, bold, italic, alignment, opacity, and box dimensions with save/reload compatibility.
4. `paper_ui.gd::_case_text_action` handles only `edit` and `bake`. The case has `set_supported_text_actions(actions)`; `duplicate` and `delete` buttons remain hidden until the workspace calls it with those supported actions. Add these through the selected annotation ID and existing request path, then enable the buttons. Bake only the selected ID, preserve visual formatting and undo history. Current bake sets `baked=true`, so visual preservation relies on the annotation renderer and undo still needs implementation.
5. A page child overlay should draw a bound around the selected object, offer resize/format/action controls adjacent to that bound, and route each change through the selected ID. The case's popup is only the property entry surface. Parent the overlay to the paper canvas so zoom and pan preserve alignment. Do not put screen coordinates into document data.

Current source checks can establish API names, exclusive tool count, and state transitions, but they cannot establish in-game appearance, hover bounds at both resolutions, actual persistence, or multiplayer correctness. Runtime screenshots and input checks remain with the runtime owner when the live-session gate permits.

## Live-path reconciliation note

This lane was instructed to be private-only. These production paths were changed before that boundary correction arrived; preserve their current contents for the main integrator to reconcile. No rollback was attempted. SHA-256 at handoff: case.gd 96D4E64 (PowerShell display truncated), body.gd 42B4A41 (display truncated), tools/CONTRACT.md CE885A5 (display truncated).

Changed live paths: scripts/ui/paper_workspace/tools/case.gd, scripts/ui/paper_workspace/tools/body.gd, scripts/ui/paper_workspace/tools/CONTRACT.md.
