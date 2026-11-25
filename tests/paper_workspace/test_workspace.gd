extends SceneTree
const Equations=preload("res://scripts/ui/paper_workspace/equations/test_equations.gd")
const Layout=preload("res://scripts/ui/paper_workspace/equations/layout.gd")
const Annotations=preload("res://scripts/paper_annotations.gd")
const Worksheet=preload("res://scripts/worksheet_page.gd")
const Ink=preload("res://scripts/paper_ink.gd")
const PaperViewport=preload("res://scripts/ui/paper_workspace/workspace/viewport.gd")
const Drawer=preload("res://scripts/ui/paper_workspace/calculator/drawer.gd")
const Calculator=preload("res://scripts/scientific_calculator.gd")
var failures: Array[String]=[]
func check(condition: bool,label: String) -> void:
	if not condition:failures.append(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	failures.append_array(Equations.run())
	var font: Font=ThemeDB.fallback_font
	var source := "((a+b)/(c+d))^2"
	var plan: Dictionary=Layout.build(source,font,24)
	check(plan.ok and plan.source==source,"equation source is exact")
	check(Annotations.measure(source,24,font,true).is_equal_approx(plan.size),"selection hit bounds match typesetter")
	var invalid := "invalid syntax ) " + "xy".repeat(30)
	var fallback := Layout.build(invalid,font,24)
	check(not fallback.ok and fallback.commands[0].text==invalid,"invalid equation keeps readable source")
	check(not Annotations.equation_error("(((33)(66)/33+66)^2) + 3)").is_empty(),"malformed grouping reports error")
	var root := Control.new();root.size=Vector2(800,600);self.root.add_child(root)
	var annotation: Variant=Annotations.new();annotation.size=Vector2(780,1100);annotation.writable=true;root.add_child(annotation)
	annotation.text_defaults={"font":"Serif","font_size":31,"angle":0.2,"equation":true}
	annotation.set_tool("text")
	var saved: Dictionary={"id":"synthetic","kind":"equation","text":source,"position":Vector2(0.2,0.2),"angle":0.2,"font_size":31,"font":"Serif","color":"263743","baked":false}
	annotation.items=[saved.duplicate(true)];annotation.selection="synthetic"
	annotation.update_selected("text","x_1^2")
	check(annotation.items[0].text=="x_1^2" and annotation.items[0].kind=="equation","selected equation edit preserves mode")
	annotation.edit_inline(annotation.items[0])
	check(is_instance_valid(annotation.inline_editor) and is_equal_approx(annotation.inline_editor.rotation,.2),"equation source edits in the existing paper control")
	annotation.inline_editor.text="(a/b)^2"
	annotation.finish_inline_edit(false)
	check(annotation.items[0].text=="x_1^2","Escape cancels uncommitted equation")
	annotation.edit_inline(annotation.items[0])
	annotation.inline_editor.text="(a/b)^2"
	annotation.finish_inline_edit()
	check(annotation.items[0].text=="(a/b)^2" and annotation.selection=="synthetic","inline equation commits and stays selected")
	var item: Dictionary=annotation.items[0]
	var extent := Annotations.measure(item.text,item.font_size,annotation._item_font(item),true)
	var bounds: Vector2=annotation._bounds(item,extent)
	var handle: Vector2=annotation._handles(bounds).rotate
	var pivot: Vector2=item.position*annotation.size+handle.rotated(item.angle)
	var press := InputEventMouseButton.new()
	press.button_index=MOUSE_BUTTON_LEFT
	press.pressed=true
	press.position=pivot
	annotation._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position=pivot+Vector2(65,15)
	annotation._gui_input(motion)
	check(not is_equal_approx(item.angle,.2) and pivot.is_equal_approx(item.position*annotation.size+handle.rotated(item.angle)),"rotation keeps the handle fixed")
	press.pressed=false
	annotation._gui_input(press)
	press.pressed=true
	var bottom: Vector2=annotation._handles(bounds).bottom
	press.position=item.position*annotation.size+bottom.rotated(item.angle)
	annotation._gui_input(press)
	motion.position=press.position+Vector2(0,90).rotated(item.angle)
	annotation._gui_input(motion)
	check(is_equal_approx(float(item.get("box_height",0.0)),bounds.y+90),"bottom handle resizes a rotated annotation vertically")
	press.pressed=false
	annotation._gui_input(press)
	annotation.update_selected("baked",true)
	check(annotation.items[0].baked and annotation.items[0].text=="(a/b)^2","bake preserves source")
	annotation.set_tool("answer");check(annotation.tool=="answer","tool deselection")
	var ink: Variant=Ink.new();ink.size=Vector2(780,1100);root.add_child(ink)
	ink.pencil_hardness=0.25;ink.pencil_opacity=0.4;ink.pencil_width=6.0;ink.current=[Vector2(0.1,0.2),Vector2(0.3,0.4)];ink.finish()
	check(ink.strokes.size()==1 and is_equal_approx(float(ink.strokes[0].hardness),0.25) and is_equal_approx(float(ink.strokes[0].opacity),0.4),"ink stroke stores actual brush properties")
	ink.eraser_radius=20.0;ink.erase_at(Vector2(156,330));check(ink.strokes.size()==2,"eraser preserves both ends of a cut stroke")
	if ink.strokes.size()==2:
		check(ink.strokes.front().points.front()==Vector2(.1,.2) and ink.strokes.back().points.back()==Vector2(.3,.4),"erase preserves original endpoints")
	var samples := PackedVector2Array([Vector2(.2,.5),Vector2(.8,.5),Vector2(.2,.5)])
	var single := PackedVector2Array([Vector2(.2,.5),Vector2(.8,.5)])
	for hardness in [0.0,.25,.5,.75,1.0]:
		for width in [3.0,12.0,24.0,32.0]:
			var repeated_mask: Dictionary=ink.rasterizer.Rasterize(samples,Vector2(780,1100),width,hardness)
			var single_mask: Dictionary=ink.rasterizer.Rasterize(single,Vector2(780,1100),width,hardness)
			var painted: Image=repeated_mask.texture.get_image()
			check(painted.get_data()==single_mask.texture.get_image().get_data(),"retracing within one stroke leaves coverage unchanged")
			var center := painted.get_pixel(painted.get_width()/2,painted.get_height()/2)
			check(center.r==1.0 and center.g==1.0 and center.b==1.0 and center.a>.4,"mask preserves color and brush center")
	var wide_line := {"points":[Vector2(.1,.5),Vector2(.9,.5)],"color":"b94745","width":28.0}
	var fragments: Array=Ink.erase_area([wide_line],Vector2(.5,.75),Vector2(.015,.010),Vector2(.5,.25))
	check(fragments.size()==2,"fast eraser movement sweeps an uninterrupted gap")
	if fragments.size()==2:
		check(fragments[0].points[-1].x<.47 and fragments[1].points[0].x>.53,"eraser clips the edge of thick ink")
	var dense: Array=[]
	for row in 120:
		var y := .15 + row*.005
		dense.append({"points":[Vector2(.1,y),Vector2(.9,y)],"color":"263743","width":2.0})
	var dense_result: Array=Ink.erase_area(dense,Vector2(.5,.9),Vector2(.015,.01),Vector2(.5,.1))
	check(dense_result.size()==240,"eraser preserves more than one hundred fragments")
	var view := PaperViewport.new()
	root.add_child(view)
	view.size=Vector2(850,650)
	var page := Control.new()
	page.size=Vector2(780,1100)
	view.mount(page)
	for factor in [view.zoom,1.0,1.5,2.0]:
		view.restore(factor,(view.size-page.size*factor)*.5)
		var prior: Vector2=view.offset
		view.move_by(Vector2(30,-25))
		check(view.offset.x>prior.x and view.offset.y<prior.y,"paper pans both ways at %.2f zoom"%factor)
	view.restore(1.0,Vector2(1e6,-1e6))
	check(view.offset.x>view.size.x*.65 and view.offset.y<-page.size.y*.55,"viewport permits wide horizontal and vertical sweeps")
	check(view.offset.x<view.size.x and view.offset.y>-page.size.y,"paper retains a visible grab area")
	var drawer: Variant=Drawer.new();root.add_child(drawer);drawer.configure(Calculator.new());drawer.set_locked(true)
	var state: Dictionary=drawer.snapshot_state();drawer.set_locked(false);drawer.restore_state(state)
	check(drawer.locked and bool(drawer.snapshot_state().locked),"calculator pin state survives rebuild snapshot")
	var sheet := Worksheet.new()
	sheet.paper={"owner_name":"Student","lesson":true,"guide":true,"strokes":{},
		"project":{"title":"Guide","difficulty":0,"source":"Fixture","course_id":"ELM253",
			"guide_pages":[{"title":"Long lesson","text":"A long instruction with several words.\n".repeat(80)}]}}
	root.add_child(sheet)
	for i in 5:await process_frame
	check(sheet.size==Worksheet.PAPER_SIZE,"long lesson uses the standard paper size")
	var printed: MarginContainer=sheet.body.get_parent()
	check(printed.scale.y<1.0,"long legacy instructions fit within the fixed sheet")
	root.queue_free()
	print("PAPER_WORKSPACE_RESULT failures=%d"%failures.size())
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
