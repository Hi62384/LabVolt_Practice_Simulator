extends SceneTree
var output:=""
func capture(name: String) -> void:
 for i in 4:await process_frame
 await RenderingServer.frame_post_draw
 var error:=root.get_texture().get_image().save_png(output+"/"+name+".png")
 if error!=OK:push_error("Capture save failed");quit(2)
func _initialize() -> void:call_deferred("run")
func run() -> void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
 if output.is_empty():quit(2);return
 var bp: Dictionary=preload("res://tests/remaining/pcb/pcb_tests.gd").fixture()
 bp.pcb_design.outline=[[0,0],[7,0],[7,5],[4,5],[4,4],[2,4],[2,5],[0,5]]
 var profile=preload("res://scripts/electronics_profile.gd").new();profile.open("outline_render_private")
 var panel:=PanelContainer.new();panel.position=Vector2(20,20);panel.size=Vector2(1240,680);root.add_child(panel)
 var scroll:=ScrollContainer.new();panel.add_child(scroll)
 var editor=preload("res://scripts/pcb_design/editor.gd").new();editor.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(editor);editor.build(profile,bp)
 await capture("visual-outline-editor")
 var view: Control=editor.view
 var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=preload("res://scripts/pcb_design/design.gd").map_point(bp,[4,4],view.rect());view._gui_input(click)
 var motion:=InputEventMouseMotion.new();motion.position=preload("res://scripts/pcb_design/design.gd").map_point(bp,[0,0],view.rect());view._gui_input(motion)
 await capture("invalid-outline-preview")
 click.pressed=false;click.position=motion.position;view._gui_input(click)
 editor.change_mode(1)
 await capture("copper-mode-preserved")
 print("OUTLINE_RENDER_CHECK captures=3 success=true")
 quit(0)
