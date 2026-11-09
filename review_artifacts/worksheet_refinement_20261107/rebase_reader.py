from pathlib import Path
import re

root = Path(__file__).parent
current = Path("scripts/paper_ui.gd").read_text(encoding="utf-8")
worksheet = (root / "paper_ui.candidate.gd").read_text(encoding="utf-8")
methods = [
    "_build_reader", "remember_view", "apply_zoom", "_clamp_pan", "_set_zoom",
    "restore_view", "_paper_input", "_input", "_workspace_input", "_paper_control_at",
    "_case_tool_selected", "_case_properties_changed", "_case_text_action", "_updated", "_process",
]
for name in methods:
    pattern = rf"(?ms)^func {re.escape(name)}\([^\n]*\).*?(?=^func |\Z)"
    found = re.search(pattern, worksheet)
    assert found, name
    replacement = found.group()
    if re.search(pattern, current):
        current = re.sub(pattern, lambda _m: replacement, current, count=1)
    else:
        anchor = "func _paper_control_at(" if name in ["_input", "_workspace_input"] else "func _case_tool_selected("
        current = current.replace(anchor, replacement + anchor, 1)
current = current.replace("var tool_case: Control\n", "var tool_case: Control\nvar workspace_view: Control\nvar awaiting_annotation_undo := false\n", 1)
current = current.replace("\tpage_view=null\n", "\tpage_view=null\n\tworkspace_view=null\n", 1)
(root / "paper_ui.candidate.gd").write_text(current, encoding="utf-8")
