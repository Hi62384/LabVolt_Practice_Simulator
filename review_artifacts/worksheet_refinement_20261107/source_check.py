"""Source and modeled data checks only; does not launch Godot."""
from pathlib import Path

root = Path(__file__).parent
ui = (root / "paper_ui.candidate.gd").read_text(encoding="utf-8")
annotations = (root / "paper_annotations.candidate.gd").read_text(encoding="utf-8")
server = (root / "school_session.candidate.gd").read_text(encoding="utf-8")
notebook = (root / "notebook_store.candidate.gd").read_text(encoding="utf-8")
case = (root / "case.candidate.gd").read_text(encoding="utf-8")
viewport = (root / "scripts/ui/paper_workspace/workspace/viewport.gd").read_text(encoding="utf-8")
ink = (root / "paper_ink.candidate.gd").read_text(encoding="utf-8")

for field in ("bold", "italic", "align", "opacity", "box_width"):
    assert all(f'"{field}"' in source for source in (ui, annotations, server, case)), field
for field in ("align", "opacity", "box_width"):
    assert f'"{field}"' in notebook, field
for action in ('"bake"', '"duplicate"', '"delete"'):
    assert action in ui and action in case, action
assert '"undo_annotation"' in ui and '"undo_annotation"' in server
assert 'annotation_history.pop_back()' in server
assert 'if bool(item.get("baked",false)):items.remove_at' in annotations
assert 'else:erase_ink.emit(event.position)' in annotations
assert 'tool_case.set_supported_text_actions(["edit","bake","duplicate","delete"])' in ui
assert 'var copy: Dictionary=source.duplicate(true)' in ui
assert 'copy.id=str(Time.get_ticks_usec())' in ui
assert 'item[key]=value;changed.emit(item.duplicate(true))' in annotations
assert '"position":event.position/size' in annotations
assert '"position":pos' in server
assert 'workspace_view.mount(page_view)' in ui
assert 'paper.scale = Vector2.ONE * zoom' in viewport
assert '_show_open_lab_instructor()' in ui
assert 'set_occlusion_rect(occupied)' in ui
assert '"hardness":pencil_hardness,"opacity":pencil_opacity' in ink
assert 'event.pressure>0.0' in ink
assert '"width":clampf(effective_width,1.0,32.0)' in ink
assert 'clampf(width,1.,32.)' in server
assert 'float(entry.get("width",0))>32' in notebook
assert 'ink.eraser_radius=clampf(float(properties.get("width",12.0)),4.0,64.0)' in ui
assert 'if is_instance_valid(tool_case):_case_properties_changed(tool_case.properties)' in ui
assert 'active_cursor_tool=cursor_tool' in ui
assert ui.count('Input.set_custom_mouse_cursor(') == 3
assert 'if bool(item.get("baked",false)):items.remove_at' in annotations

# The server stores every new field and preserves legacy defaults on reload.
sample = dict(id="23", kind="text", text="a\nb", position=(0.25, 0.4),
              font="Sans", font_size=27, angle=0.0, color="263743",
              bold=True, italic=True, align="center", opacity=0.65,
              box_width=320.0, baked=True)
saved = {key: sample[key] for key in sample}
assert saved == sample
legacy = dict(id="22", kind="text", text="old", position=(0.1, 0.2),
              font="Sans", font_size=24, angle=0.0, color="263743", baked=False)
assert legacy.get("bold", False) is False
assert legacy.get("italic", False) is False
assert legacy.get("align", "left") == "left"
assert legacy.get("opacity", 1.0) == 1.0
assert legacy.get("box_width", 280.0) == 280.0
history = [{"page": "0", "id": sample["id"], "before": legacy}]
restored = history.pop()["before"]
assert restored == legacy

print("Source and modeled data checks passed; GDScript/runtime untested")
