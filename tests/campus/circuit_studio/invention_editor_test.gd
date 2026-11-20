extends SceneTree
## Real assembly-window widget path, with an isolated source-game profile.
const Model=preload("res://scripts/campus/facilities/circuit_studio/assembly_model.gd")
const WindowScript=preload("res://scripts/campus/facilities/circuit_studio/assembly_window.gd")
const Board=preload("res://scripts/breadboard_model.gd")
const Custom=preload("res://scripts/custom_circuit.gd")

func _initialize() -> void:
	call_deferred("_run")

func _button(parent: Node,label: String) -> Button:
	for node in parent.find_children("*","Button",true,false):
		if node.text==label:return node
	return null

func _choose(choice: OptionButton,value: Variant) -> bool:
	for index in choice.item_count:
		if choice.get_item_metadata(index)==value:
			choice.select(index)
			return true
	return false

func _run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for frame in 4:await process_frame
	# An editor opened through real gameplay already has an active character.
	# This isolated SceneTree fixture bypasses the menu and must create one.
	# Use a fresh identity so the test never touches a player's saved profile.
	var identity:=Crypto.new().generate_random_bytes(12).hex_encode()
	game.electronics.profile.open(identity)
	# An untouched starter profile legitimately omits the optional blueprints
	# map until the first PCB is saved. Supply it for this fixture's PCB edit.
	if not game.electronics.profile.data.has("blueprints"):
		game.electronics.profile.data.blueprints={}
	assert(game.electronics.profile.data.get("blueprints") is Dictionary,
		"Test PCB library must be initialized before the editor manipulates it")
	var window=WindowScript.new()
	game.add_child(window)
	window.open_station(game)
	var old_profile: Dictionary=game.electronics.profile.data.duplicate(true)
	# Check the same raycast normalization used by the interactive game.
	var fake_invention:=StaticBody3D.new()
	fake_invention.set_meta("role","invention")
	var fake_solid:=StaticBody3D.new()
	fake_solid.name="Solid"
	fake_invention.add_child(fake_solid)
	game.add_child(fake_invention)
	assert(game._resolve_invention_hit(fake_solid)==fake_invention,"Physical invention target lost the retrieve interaction")
	fake_invention.queue_free()
	var draft: Dictionary=Model.empty("Editor checks")
	draft.parts.append_array([
		{"type":"battery","x":1,"y":0,"z":0,"control":"","ref":""},
		{"type":"switch","x":2,"y":0,"z":0,"control":"A","ref":""},
		{"type":"switch","x":3,"y":0,"z":0,"control":"B","ref":""},
		{"type":"servo","x":0,"y":1,"z":0,"control":"A","ref":""}
	])
	assert(Model.validate("inv:test",{"inv:test":draft},old_profile.get("blueprints",{}))=="")
	window.draft=draft
	window.selected_part=4
	window._editor()
	assert(window.part_kind.get_item_metadata(window.part_kind.selected)=="servo","Selection must use the existing part type")
	assert(window.part_control.selected==1,"Selection must display its saved A channel")
	assert(window.part_x.value==0 and window.part_y.value==1,"Selected coordinates were not populated")
	window.part_control.select(2)
	window.part_x.value=4
	window._apply_selected()
	assert(window.draft.parts[4].control=="B" and window.draft.parts[4].x==4,"Apply did not update the selected servo")
	assert(Model.validate("inv:test",{"inv:test":window.draft},old_profile.get("blueprints",{}))=="")
	assert(window.undo_stack.size()==1,"Editing an existing part must be undoable")
	var part_count: int=window.draft.parts.size()
	window.part_x.value=0
	window.part_y.value=0
	window.part_z.value=0
	window._add_part()
	assert(window.draft.parts.size()==part_count and window.notice.text.contains("occupies"),"Add Part must reject an already occupied cell")
	window._history(window.undo_stack,window.redo_stack)
	assert(window.draft.parts[4].control=="A" and window.draft.parts[4].x==0,"Undo lost the original properties")
	window._history(window.redo_stack,window.undo_stack)
	assert(window.draft.parts[4].control=="B" and window.draft.parts[4].x==4,"Redo did not restore edited properties")
	window.selected_part=4
	window._editor()
	window.part_x.value=5
	window._viewport_click(Vector3i(3,0,0),3)
	assert(window.draft.parts[4].x==5 and window.selected_part==3,
		"Selecting another part silently discarded edits to the previous selection")
	window._viewport_click(Vector3i(6,0,6),-1)
	assert(window.selected_part==-1,"Clicking empty grid space must deselect a part")
	window._history(window.undo_stack,window.redo_stack)
	assert(window.draft.parts[4].x==4,"Undo must revert selection-committed coordinate changes")
	window._history(window.redo_stack,window.undo_stack)
	assert(window.draft.parts[4].x==5,"Redo must restore selection-committed coordinate changes")
	# Test uses pending inspector coordinates even without clicking Apply.
	window.selected_part=4
	window._editor()
	window.part_x.value=5
	# The library is also a placement palette. Merely browsing it must not
	# replace the selected servo during Save/Test without explicit Apply.
	for kind_index in window.part_kind.item_count:
		if str(window.part_kind.get_item_metadata(kind_index))=="wood_frame":
			window.part_kind.select(kind_index)
			break
	window._reference_options()
	window.draft.controls={"A":"hold","B":"toggle"}
	window._test_draft()
	assert(window.draft.parts[4].x==5,"Test silently discarded an unapplied inspector edit")
	assert(window.draft.parts[4].type=="servo",
		"Changing the placement palette silently replaced a selected part")
	window._editor()
	window.part_x.value=4
	window._apply_selected()
	window._test_draft()
	await process_frame
	var hold:=_button(window,"Hold A")
	var toggle:=_button(window,"Switch B")
	assert(is_instance_valid(hold) and is_instance_valid(toggle),"Test controls must match configured hold and toggle modes")
	hold.button_down.emit()
	assert(window.test_switches.A,"Holding A did not energize the test input")
	hold.button_up.emit()
	assert(not window.test_switches.A,"Releasing A did not deenergize the test input")
	toggle.pressed.emit()
	assert(window.test_switches.B,"Toggle B did not latch its test input")
	toggle.pressed.emit()
	assert(not window.test_switches.B,"Second B press did not release its test input")
	
	var board: Dictionary=Board.empty()
	board.parts=[
		{"id":"gate","type":"toggle","a":"A1","b":"A2"},
		{"id":"load","type":"r1000","a":"A2","b":"F1"}
	]
	var bp: Dictionary=Board.blueprint(board,"Editor test PCB")
	bp.package="PCB"
	bp.footprint={"width":8,"height":8,"color":"24775b"}
	bp.layout={"rows":30,"parts":board.parts.duplicate(true),"wires":[]}
	bp.pins=[
		{"name":"VCC","node":"L1"},
		{"name":"GND","node":"R1"},
		{"name":"OUT_A","node":"L2"},
		{"name":"OUT_B","node":"R2"}
	]
	var id: String="ic:editor_regression"
	assert(Custom.validate(id,{id:bp})=="")
	game.electronics.profile.data.blueprints[id]=bp
	window.draft.parts.append({
		"type":"pcb","x":5,"y":0,"z":0,"control":"","ref":id,
		"pin_map":{"power":0,"ground":1,"A":2,"B":3}
	})
	window.selected_part=window.draft.parts.size()-1
	window._editor()
	assert(window.part_kind.get_item_metadata(window.part_kind.selected)=="pcb","Selected PCB type must be retained")
	assert(window.part_ref.get_item_metadata(window.part_ref.selected)==id,"Selected PCB blueprint reference was not restored")
	assert(int(window.pin_choices.A.get_item_metadata(window.pin_choices.A.selected))==2,"Selected PCB output A was not restored")
	assert(_choose(window.pin_choices.A,3),"Output A should offer the fourth PCB pin")
	assert(_choose(window.pin_choices.B,2),"Output B should offer the third PCB pin")
	window._apply_selected()
	var updated: Dictionary=window.draft.parts.back()
	assert(updated.pin_map.A==3 and updated.pin_map.B==2,"Apply must update the existing PCB pin map")
	assert(Model.validate("inv:test",{"inv:test":window.draft},game.electronics.profile.data.blueprints)=="")
	# A nested child with no individual copies must still get a new revision
	# when its parent was fabricated. The parent keeps referring to the old ID.
	var child: Dictionary=Model.empty("Nested child")
	var parent: Dictionary=Model.empty("Fabricated parent")
	parent.parts.append({"type":"nested","x":1,"y":0,"z":0,"control":"","ref":"inv:child"})
	game.electronics.profile.data.inventions={"inv:child":child,"inv:parent":parent}
	game.electronics.profile.data.invention_copies={"inv:parent":1}
	var nested_preview=preload("res://scripts/campus/facilities/circuit_studio/assembly_preview.gd").new()
	nested_preview.design=parent
	nested_preview.library={"inv:preview":parent,"inv:child":child}
	nested_preview.pcbs=game.electronics.profile.data.blueprints
	game.add_child(nested_preview)
	assert(nested_preview._selection_bounds.any(func(entry):return entry.index==1 and float(entry.bounds.position.x)>.1),"Expanded nested parts need selectable hit regions")
	nested_preview.queue_free()
	window.editing_id="inv:child"
	window.draft=child.duplicate(true)
	window.draft.parts.append({"type":"plastic_shell","x":2,"y":0,"z":0,"control":"","ref":""})
	window.selected_part=1
	window._editor()
	window.part_x.value=3
	assert(window._draft_error()=="","A revised child must be validated independently of the frozen parent")
	window._save()
	assert(window.draft.parts[1].x==3,"Save silently discarded pending inspector coordinates")
	assert(window.editing_id=="inv:child","Original editing identity should remain unchanged by saving")
	assert(game.electronics.profile.data.inventions["inv:child"]==child,"Fabricated parent's child blueprint changed in place")
	assert(game.electronics.profile.data.inventions["inv:parent"].parts[1].ref=="inv:child","Fabricated parent was silently rewired to a new child")
	assert(game.electronics.profile.data.inventions.size()==3,"A fresh revision should be saved")
	assert(window._finish_discard("inv:parent")=="","Singleplayer must allow returning unused fabricated copies")
	assert(not game.electronics.profile.data.invention_copies.has("inv:parent"),"Discarded copy count was retained")
	assert(game.electronics.profile.data.inventions.has("inv:parent"),"Discard should preserve the blueprint")
	window._remove("inv:parent")
	assert(not game.electronics.profile.data.inventions.has("inv:parent"),"An unreferenced blueprint should be removable after its copies are cleared")
	# Valid pre-drive-map blueprints must still enter Test from the library.
	var legacy: Dictionary=Model.empty("Legacy manual drive")
	legacy.erase("drive")
	assert(Model.validate("inv:legacy",{"inv:legacy":legacy},game.electronics.profile.data.blueprints)=="")
	window._library()
	window.draft=legacy
	window._test_draft()
	assert(window.page=="test" and window.draft.drive=={"A":"manual","B":"manual"},
		"Legacy invention preview crashed or lost the default manual drive")
	game.electronics.profile.data=old_profile
	window._close()
	await process_frame
	game.queue_free()
	await process_frame
	print("INVENTION_EDITOR PASS")
	quit()
