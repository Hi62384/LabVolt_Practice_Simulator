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
	# Two saved revisions can have the same title; distinguish them in
	# the library, and keep all per-blueprint actions accessible at low widths.
	game.electronics.profile.data.inventions={"inv:rev-one":Model.empty("Same name"),"inv:rev-two":Model.empty("Same name")}
	game.electronics.profile.data.invention_copies={}
	window._library()
	var revision_labels: Array=window.find_children("*","Label",true,false).filter(
		func(label):return label.text.begins_with("Same name"))
	assert(revision_labels.size()==2 and revision_labels[0].text!=revision_labels[1].text,
		"Same-named saved revisions are indistinguishable in the library")
	assert(_button(window,"Remove blueprint").get_parent() is HFlowContainer,
		"Blueprint buttons must wrap instead of being clipped on narrow windows")
	game.electronics.profile.data=old_profile.duplicate(true)
	window._library()
	# Creating a new invention starts with a frame at (0,0,0); the
	# editor should offer a free position instead of a failing Add part.
	window.editing_id=""
	window.draft=Model.empty("Fast assembly")
	window.selected_part=-1
	window._editor()
	assert(window.part_x.value!=0.0 or window.part_y.value!=0.0 or window.part_z.value!=0.0,
		"New invention defaults Add part to the occupied starter-frame cell")
	window._add_part()
	assert(window.draft.parts.size()==2,
		"First Add part must work without manually correcting a collision")
	# The next Add/Place should propose a different empty cell without a
	# forced deselect or overwriting the newly added part.
	window._add_part()
	assert(window.draft.parts.size()==3 and window.selected_part==-1,
		"Adding successive parts requires unexpected manual deselection")
	# Check the same raycast normalization used by the interactive game.
	var fake_invention:=StaticBody3D.new()
	fake_invention.set_meta("role","invention")
	var fake_solid:=StaticBody3D.new()
	fake_solid.name="Solid"
	fake_invention.add_child(fake_solid)
	game.add_child(fake_invention)
	assert(game._resolve_invention_hit(fake_solid)==fake_invention,"Physical invention target lost the retrieve interaction")
	fake_invention.queue_free()
	# A new draft's name, control mode and drive mode are visible edits.
	# Undo must revert them before an unrelated edit; Redo restores them.
	window._library()
	window.editing_id=""
	window.draft=Model.empty("History draft")
	window.selected_part=-1
	window._editor()
	window.name_field.text="Edited title"
	window.mode_a.select(1)
	window.drive_a.select(1)
	window._history(window.undo_stack,window.redo_stack)
	assert(window.draft.name=="History draft" and window.draft.controls.A=="hold" and window.draft.drive.A=="manual",
		"Undo lost the baseline or skipped uncommitted name/drive settings")
	var redo_shortcut:=InputEventKey.new()
	redo_shortcut.pressed=true
	redo_shortcut.ctrl_pressed=true
	redo_shortcut.shift_pressed=true
	redo_shortcut.keycode=KEY_Z
	window._unhandled_key_input(redo_shortcut)
	assert(window.draft.name=="Edited title" and window.draft.controls.A=="toggle" and window.draft.drive.A=="pcb",
		"Redo did not restore staged name, control and drive settings")
	window._library()
	# Switching to Place from a clean selected part must not modify or move it,
	# and consecutive canvas clicks must create consecutive new parts.
	window.draft=Model.empty("Place tool test")
	window.draft.parts.append({"type":"plastic_shell","x":1,"y":0,"z":0,"control":"","ref":""})
	window.selected_part=1
	window._editor()
	assert(_button(window,"Undo").get_parent() is HFlowContainer,
		"Editor toolbar must wrap Undo and Redo on smaller displays")
	window.viewport_tool="place"
	window._viewport_click(Vector3i(2,0,0),-1)
	assert(window.draft.parts.size()==3 and window.draft.parts[1].x==1 and window.selected_part==-1,
		"Place modified the selected part instead of creating another")
	window._viewport_click(Vector3i(3,0,0),-1)
	assert(window.draft.parts.size()==4 and window.draft.parts[3].x==3,
		"Consecutive Place clicks did not add separate parts")
	window._library()
	var draft: Dictionary=Model.empty("Editor checks")
	draft.parts.append_array([
		{"type":"battery","x":1,"y":0,"z":0,"control":"","ref":""},
		{"type":"switch","x":2,"y":0,"z":0,"control":"A","ref":""},
		{"type":"switch","x":3,"y":0,"z":0,"control":"B","ref":""},
		{"type":"servo","x":0,"y":1,"z":0,"control":"A","ref":""}
	])
	assert(Model.validate("inv:test",{"inv:test":draft},old_profile.get("blueprints",{}))=="")
	# This fixture replaces the first draft directly. Real users return via
	# the Library, which clears the prior design's undo/redo stacks.
	window._library()
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
	# Add must not discard an un-applied edit to the selected actuator.
	window.part_x.value=5
	window.part_control.select(1)
	window._add_part()
	assert(window.draft.parts.size()==part_count and window.draft.parts[4].control=="B" and window.notice.text.contains("Apply"),
		"Add silently replaced an unapplied selected-part change")
	window.part_control.select(2)
	window.part_x.value=0
	window.part_y.value=0
	window.part_z.value=0
	window._add_part()
	assert(window.draft.parts.size()==part_count and window.notice.text.contains("occupies"),"Add Part must reject an already occupied cell")
	window._history(window.undo_stack,window.redo_stack)
	assert(window.draft.parts[4].control=="A" and window.draft.parts[4].x==0,"Undo lost the original properties")
	window._history(window.redo_stack,window.undo_stack)
	assert(window.draft.parts[4].control=="B" and window.draft.parts[4].x==4,"Redo did not restore edited properties")
	# Undo while an inspector coordinate is still staged must first undo
	# that coordinate, rather than popping an older unrelated snapshot.
	window.selected_part=4
	window._editor()
	window.part_x.value=5
	window._history(window.undo_stack,window.redo_stack)
	assert(window.draft.parts[4].x==4,"Undo skipped the currently visible uncommitted position")
	window._history(window.redo_stack,window.undo_stack)
	assert(window.draft.parts[4].x==5,"Redo lost the pending inspector position")
	window._history(window.undo_stack,window.redo_stack)
	assert(window.draft.parts[4].x==4)
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
	# Escape from a tool must not throw away inspector changes, and those
	# committed changes must remain a normal undoable edit.
	window.selected_part=4
	window._editor()
	window.viewport_tool="move"
	window.part_x.value=6
	var escape_event:=InputEventKey.new()
	escape_event.keycode=KEY_ESCAPE
	escape_event.pressed=true
	window._unhandled_key_input(escape_event)
	assert(window.viewport_tool=="select" and window.draft.parts[4].x==6,
		"Escape discarded pending inspector changes when leaving move mode")
	window._history(window.undo_stack,window.redo_stack)
	assert(window.draft.parts[4].x==5,"Undo must restore the pre-Escape part position")
	# Moving a selected part must commit its staged control alongside position
	# rather than silently reverting the inspector's unapplied change.
	window.selected_part=4
	window._editor()
	window.viewport_tool="move"
	window.part_control.select(1)
	window._viewport_click(Vector3i(6,1,0),-1)
	assert(window.draft.parts[4].x==6 and window.draft.parts[4].control=="A",
		"Moving a part discarded its pending control assignment")
	window._history(window.undo_stack,window.redo_stack)
	assert(window.draft.parts[4].x==5 and window.draft.parts[4].control=="B",
		"Undo must restore position and control together")
	# A valid draft must react to pending inspector edits immediately; neither
	# Save nor Test should accept an unassigned actuator or overlapping cells.
	window.selected_part=4
	window._editor()
	var save_button:=_button(window,"Save blueprint")
	var test_button:=_button(window,"Test")
	assert(not save_button.disabled and not test_button.disabled)
	window.part_control.select(0)
	window.part_control.item_selected.emit(0)
	assert(save_button.disabled and test_button.disabled,
		"Pending invalid actuator control left Save/Test enabled")
	window._test_draft()
	assert(window.page=="editor" and window.notice.text.contains("Assign each motor"),
		"Test accepted a physically invalid staged invention")
	window.part_control.select(2)
	window.part_control.item_selected.emit(2)
	assert(not save_button.disabled and not test_button.disabled,
		"Correcting the control did not reenable Save/Test")
	window.part_x.value=0
	window.part_y.value=0
	assert(save_button.disabled and test_button.disabled,
		"Overlapping pending coordinates were not validated live")
	window.part_x.value=5
	window.part_y.value=1
	assert(not save_button.disabled and not test_button.disabled,
		"Correcting overlapping coordinates did not restore Save/Test")
	window._apply_selected()
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
	# Place an alternate PCB before the selected one so changing the palette
	# cannot accidentally pass by reverting to the library's first entry.
	var alternative: Dictionary=bp.duplicate(true)
	alternative.name="Spare PCB"
	game.electronics.profile.data.blueprints["ic:aaa_spare"]=alternative
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
	# Searching for another part temporarily hides PCB selectors; returning to
	# PCB must preserve both the referenced blueprint and un-applied pin edits.
	assert(_choose(window.pin_choices.A,2) and _choose(window.pin_choices.B,3))
	window._fill_parts("wood")
	window._fill_parts("pcb")
	assert(window.part_kind.get_item_metadata(window.part_kind.selected)=="pcb")
	assert(window.part_ref.get_item_metadata(window.part_ref.selected)==id,
		"Filtering the part palette lost the selected PCB reference")
	assert(int(window.pin_choices.A.get_item_metadata(window.pin_choices.A.selected))==2
		and int(window.pin_choices.B.get_item_metadata(window.pin_choices.B.selected))==3,
		"Filtering the part palette reset pending PCB output pins")
	assert(window._draft_error()=="","Restored PCB pin settings must remain valid")
	assert(window._commit_selected_changes())
	assert(window.draft.parts.back().pin_map.A==2 and window.draft.parts.back().pin_map.B==3,
		"Committed PCB pins must match the selections after a palette search")
	assert(Model.validate("inv:test",{"inv:test":window.draft},game.electronics.profile.data.blueprints)=="")
	# Imported PCBs may have generic pin labels instead of VCC/GND.
	# The first-time mapping should select distinct supply pins automatically.
	var generic_bp: Dictionary=bp.duplicate(true)
	for index in generic_bp.pins.size():generic_bp.pins[index].name="Pin "+str(index+1)
	var generic_id: String="ic:generic_labels"
	assert(Custom.validate(generic_id,{generic_id:generic_bp})=="")
	game.electronics.profile.data.blueprints[generic_id]=generic_bp
	window.selected_part=-1
	window._editor()
	for index in window.part_kind.item_count:
		if window.part_kind.get_item_metadata(index)=="pcb":window.part_kind.select(index);break
	window._reference_options()
	for index in window.part_ref.item_count:
		if window.part_ref.get_item_metadata(index)==generic_id:window.part_ref.select(index);break
	window._pin_options()
	var default_pins: Dictionary={}
	for role in ["power","ground","A","B"]:
		var selector: OptionButton=window.pin_choices[role]
		assert(selector.selected>=0,"Default PCB pin selector is unconfigured")
		default_pins[role]=int(selector.get_item_metadata(selector.selected))
	assert(default_pins.power==0 and default_pins.ground==1 and Model.validate_pcb_pin_map(generic_bp,default_pins)=="",
		"Generically named PCB pins must default to distinct, valid supply connectors")
	# A missing pin selection on a new PCB must not read item metadata at -1,
	# silently default to pin zero, or add a partially mapped board.
	var before_unmapped: int=window.draft.parts.size()
	window.pin_choices.A.select(-1)
	window._add_part()
	assert(window.draft.parts.size()==before_unmapped and window.notice.text.contains("Configure PCB"),
		"Adding a PCB with a missing pin selection must fail without changing the draft")
	window._pin_options()
	# A cleared PCB reference must not make the inspector read metadata at -1.
	var previous_count: int=window.draft.parts.size()
	window.part_ref.select(-1)
	window._pin_options()
	assert(window.pin_choices.is_empty(),"Unselected PCB references must have no pin mapping controls")
	window._add_part()
	assert(window.draft.parts.size()==previous_count and window.notice.text.contains("blueprint"),
		"Adding a PCB without a selected blueprint must fail safely with feedback")
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
	window._discard_copies("inv:parent")
	var copies_dialogs: Array=window.get_children().filter(func(node):return node is ConfirmationDialog and node.title.contains("Discard fabricated"))
	assert(copies_dialogs.size()==1,"Discard copies must open exactly one confirmation")
	var first_copies: ConfirmationDialog=copies_dialogs[0]
	first_copies.canceled.emit()
	window._discard_copies("inv:parent")
	copies_dialogs=window.get_children().filter(func(node):return node is ConfirmationDialog and node.title.contains("Discard fabricated"))
	assert(copies_dialogs.size()==1 and copies_dialogs[0]==first_copies,
		"Cancel and immediate reopen must reuse the fabricated-copies dialog")
	first_copies.canceled.emit()
	assert(window._finish_discard("inv:parent")=="","Singleplayer must allow returning unused fabricated copies")
	assert(not game.electronics.profile.data.invention_copies.has("inv:parent"),"Discarded copy count was retained")
	assert(game.electronics.profile.data.inventions.has("inv:parent"),"Discard should preserve the blueprint")
	window._request_remove("inv:parent")
	assert(game.electronics.profile.data.inventions.has("inv:parent"),
		"Clicking Remove must not delete a blueprint before confirmation")
	var remove_dialogs: Array=window.get_children().filter(func(node):return node is ConfirmationDialog and node.title.contains("Remove invention"))
	assert(remove_dialogs.size()==1,"Blueprint deletion must show a meaningful confirmation")
	var first_remove: ConfirmationDialog=remove_dialogs[0]
	first_remove.canceled.emit()
	window._request_remove("inv:parent")
	remove_dialogs=window.get_children().filter(func(node):return node is ConfirmationDialog and node.title.contains("Remove invention"))
	assert(remove_dialogs.size()==1 and remove_dialogs[0]==first_remove,
		"Cancel and immediate reopen must reuse the remove-blueprint dialog")
	remove_dialogs[0].confirmed.emit()
	assert(not game.electronics.profile.data.inventions.has("inv:parent"),"Confirmed unreferenced blueprint was not removed")
	# Leaving the editor must also protect an unapplied inspector edit.
	window.editing_id="inv:child"
	window.draft=child.duplicate(true)
	window.selected_part=0
	window._editor()
	window.part_x.value=1
	assert(window._has_unsaved_changes(),"Pending coordinates should mark the editor dirty")
	window._go_library()
	assert(window.page=="editor","Unsaved work must remain until the player confirms a discard")
	var discard_dialogs: Array=window.get_children().filter(func(node):return node is ConfirmationDialog)
	assert(discard_dialogs.size()==1 and discard_dialogs[0].title.contains("Discard"),
		"Unsaved editor changes must show a discard confirmation")
	var first_discard: ConfirmationDialog=discard_dialogs[0]
	first_discard.canceled.emit()
	assert(window.page=="editor","Cancelling discard must preserve the editor")
	window._go_library()
	discard_dialogs=window.get_children().filter(func(node):return node is ConfirmationDialog and not node.is_queued_for_deletion())
	assert(discard_dialogs.size()==1 and discard_dialogs[0]==first_discard,
		"Cancel and immediate reopen must reuse the existing exclusive discard dialog")
	discard_dialogs[0].confirmed.emit()
	assert(window.page=="library","Confirmed discard must return to the library")
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
	window._close_now()
	await process_frame
	game.queue_free()
	await process_frame
	print("INVENTION_EDITOR PASS")
	quit()
