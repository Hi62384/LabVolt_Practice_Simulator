from pathlib import Path
import difflib,hashlib
root=Path(__file__).resolve().parents[2]
source=root/'scripts/paper_ui.gd'
old=source.read_text(encoding='utf-8-sig')
new=old
def edit(a,b):
 global new
 if new.count(a)!=1:raise RuntimeError('paper_ui anchor '+str(new.count(a))+': '+a[:50])
 new=new.replace(a,b,1)
edit('var reading := false','var reading := false\nvar open_lab_instructor_visible := false')
edit('''func close() -> void:
\tremember_view()''','''func close() -> void:
\topen_lab_instructor_visible=false
\tscreen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
\tscreen.offset_left=40;screen.offset_top=20;screen.offset_right=-40;screen.offset_bottom=-20
\tremember_view()''')
edit('''func teacher() -> void:
\tflush()''','''func teacher() -> void:
\topen_lab_instructor_visible=school.mode=="Open Lab"
\tif open_lab_instructor_visible:
\t\t_show_open_lab_instructor()
\t\treturn
\tflush()''')
edit('''func open_sheet(id: int) -> void:
\tif not school.papers.has(id):return''','''func open_sheet(id: int) -> void:
\tif not school.papers.has(id):return
\topen_lab_instructor_visible=false
\tscreen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
\tscreen.offset_left=40;screen.offset_top=20;screen.offset_right=-40;screen.offset_bottom=-20''')
edit('''func _build_freeplay_teacher_controls() -> void:''','''func _show_open_lab_instructor() -> void:
\tflush()
\treading=false
\t_clear()
\tgame.release_mouse()
\tscreen.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
\tscreen.custom_minimum_size=Vector2(480,260)
\tscreen.size=Vector2(480,260)
\tscreen.position=(get_viewport().get_visible_rect().size-screen.size)*0.5
\tscreen.show()
\tpreload("res://review_artifacts/open_lab_instructor_20261107/open_lab_panel.gd").mount(column,
\t\tfunc():
\t\t\tif school.mode!="Open Lab":return
\t\t\tschool.request({"op":"open_lab_practice"})
\t\t\tclose(),
\t\tfunc():
\t\t\tif school.mode!="Open Lab":return
\t\t\tif game.has_method("open_lab_equipment_tutorial"):
\t\t\t\tclose()
\t\t\t\tgame.call("open_lab_equipment_tutorial")
\t\t\telse:_label(column,"Equipment tutorial is unavailable in this laboratory."),
\t\tclose)
	var first: Button=column.find_children("*","Button",true,false)[0]
	first.grab_focus()

func _unhandled_key_input(event: InputEvent) -> void:
	if open_lab_instructor_visible and screen.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func _build_freeplay_teacher_controls() -> void:''')
new=new.replace('\t\t_button(column,"Equipment guide",func():school.request({"op":"guide"});close())','\t\tif preload("res://review_artifacts/open_lab_instructor_20261107/tutorials/formal_guide_policy.gd").allowed(school.mode,assigned):_button(column,"Equipment guide",func():school.request({"op":"guide"});close())',1)
new=new.replace('open_lab_instructor_visible=school.mode=="Open Lab"','open_lab_instructor_visible=school.mode in ["Open Lab","Freeplay","Creative Freeplay"]',1)
new=new.replace('if school.mode!="Open Lab":return','if school.mode not in ["Open Lab","Freeplay","Creative Freeplay"]:return')
start=new.index('\tpreload("res://review_artifacts/open_lab_instructor_20261107/open_lab_panel.gd").mount(column,')
end=new.index('\tvar first: Button=',start)
new=new[:start]+'\tpreload("res://review_artifacts/open_lab_instructor_20261107/open_lab_panel.gd").mount(column,_request_open_lab_practice,_open_lab_tutorial,close)\n'+new[end:]
hook='func _unhandled_key_input(event: InputEvent) -> void:'
new=new.replace('\tvar first: Button=column.find_children("*","Button",true,false)[0]','\tvar first := column.find_children("*","Button",true,false)[0] as Button')
new=new.replace(hook,'''func _request_open_lab_practice() -> void:
\tif school.mode!="Open Lab":return
\tschool.request({"op":"practice_lesson"})
\tclose()

func _open_lab_tutorial() -> void:
\tif school.mode!="Open Lab":return
\tif game.has_method("open_lab_equipment_tutorial"):
\t\tclose()
\t\tgame.call("open_lab_equipment_tutorial")
\telse:_label(column,"Equipment tutorial is unavailable in this laboratory.")

'''+hook,1)
target=Path(__file__).resolve().parent
(target/'paper_ui.patch').write_text(''.join(difflib.unified_diff(old.splitlines(True),new.splitlines(True),'a/scripts/paper_ui.gd','b/scripts/paper_ui.gd')),encoding='utf-8')
(target/'paper_ui.sha256').write_text(hashlib.sha256(source.read_bytes()).hexdigest()+'\n',encoding='utf-8')
