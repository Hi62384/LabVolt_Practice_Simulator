extends SceneTree
const Equations=preload("res://scripts/ui/paper_workspace/equations/test_equations.gd")
const Layout=preload("res://scripts/ui/paper_workspace/equations/layout.gd")
const Annotations=preload("res://scripts/paper_annotations.gd")
const Ink=preload("res://scripts/paper_ink.gd")
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
	check(not Annotations.equation_error("(((33)(66)/33+66)^2) + 3)").is_empty(),"malformed grouping reports error")
	var root := Control.new();root.size=Vector2(800,600);self.root.add_child(root)
	var annotation: Variant=Annotations.new();annotation.size=Vector2(780,1100);annotation.writable=true;root.add_child(annotation)
	annotation.text_defaults={"font":"Serif","font_size":31,"angle":0.2,"equation":true}
	annotation.set_tool("text")
	var saved: Dictionary={"id":"synthetic","kind":"equation","text":source,"position":Vector2(0.2,0.2),"angle":0.2,"font_size":31,"font":"Serif","color":"263743","baked":false}
	annotation.items=[saved.duplicate(true)];annotation.selection="synthetic"
	annotation.update_selected("text","x_1^2")
	check(annotation.items[0].text=="x_1^2" and annotation.items[0].kind=="equation","selected equation edit preserves mode")
	annotation.update_selected("baked",true)
	check(annotation.items[0].baked and annotation.items[0].text=="x_1^2","bake preserves source")
	annotation.set_tool("answer");check(annotation.tool=="answer","tool deselection")
	var ink: Variant=Ink.new();ink.size=Vector2(780,1100);root.add_child(ink)
	ink.pencil_hardness=0.25;ink.pencil_opacity=0.4;ink.pencil_width=6.0;ink.current=[Vector2(0.1,0.2),Vector2(0.3,0.4)];ink.finish()
	check(ink.strokes.size()==1 and is_equal_approx(float(ink.strokes[0].hardness),0.25) and is_equal_approx(float(ink.strokes[0].opacity),0.4),"ink stroke stores actual brush properties")
	ink.eraser_radius=20.0;ink.erase_at(Vector2(156,330));check(ink.strokes.is_empty(),"eraser radius removes nearby stroke")
	var drawer: Variant=Drawer.new();root.add_child(drawer);drawer.configure(Calculator.new());drawer.set_locked(true)
	var state: Dictionary=drawer.snapshot_state();drawer.set_locked(false);drawer.restore_state(state)
	check(drawer.locked and bool(drawer.snapshot_state().locked),"calculator pin state survives rebuild snapshot")
	root.queue_free()
	print("PAPER_WORKSPACE_RESULT failures=%d"%failures.size())
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
