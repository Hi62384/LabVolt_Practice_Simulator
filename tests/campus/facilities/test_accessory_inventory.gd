extends SceneTree
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:failures.append(message)
func _initialize() -> void:call_deferred("run")
func button(parent: Node,label: String) -> Button:
	for node in parent.find_children("*","Button",true,false):
		if node.text==label and node.is_visible_in_tree():return node
	return null
func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	var single:=button(game.front.body,"Singleplayer")
	if single==null:check(false,"singleplayer missing")
	else:
		single.pressed.emit();await process_frame
		var play:=button(game.front.body,"Play")
		if play==null:check(false,"play missing")
		else:play.pressed.emit();await process_frame
	if game.front.in_game:
		var dorm: Dictionary=game.electronics.profile.data.dorm
		dorm.worn_supplies={"head":"lab_goggles"}
		dorm.backpacks={"bag":{"location":"back","size":"backpack_small","items":[]}}
		game.electronics.profile.data.avatar_cosmetics={"version":1,"body":{},"equipped":{"head":{"id":"accessory.head.campus_cap","parameters":{}}}}
		game.gym_barbells.belts[0].owner=1;game.gym_barbells.belts[0].where="worn"
		game.hotbar.accessory_positions={"goggles":3,"backpack":1,"belt":0,"cosmetic/head":2}
		var view:=VBoxContainer.new();root.add_child(view);game.hotbar.manager(view)
		var labels:=[]
		for child in view.find_children("*","Button",true,false):
			if child.text.begins_with("Slot "):labels.append(child.text)
		check(labels.size()==4,"inventory did not create four accessory slots")
		check(labels.any(func(s):return s.begins_with("Slot 1") and s.contains("belt")),"belt not placed in requested slot")
		check(labels.any(func(s):return s.begins_with("Slot 4") and s.contains("goggles")),"goggles not placed in requested slot")
		check(labels.any(func(s):return s.begins_with("Slot 3") and s.contains("Campus Five-Panel Cap")),"cosmetic hat missing from accessory slots")
		game.electronics.profile.data.avatar_cosmetics.equipped["neck"]={"id":"accessory.neck.existing","parameters":{}}
		var overflow:=VBoxContainer.new();root.add_child(overflow);game.hotbar.manager(overflow)
		check(overflow.find_children("*","Button",true,false).any(func(b):return b.text.begins_with("Remove extra")),"legacy overflow could not be removed")
		overflow.free()
		view.free()
	else:check(false,"could not enter gameplay")
	game.queue_free();await process_frame
	for failure in failures:push_error(failure)
	print("ACCESSORY_INVENTORY ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
