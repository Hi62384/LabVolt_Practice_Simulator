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
		var base: float=game.carry_load.mass_for(1)
		var gear: Node=game.gym_barbells
		gear.belts[0].owner=1;gear.belts[0].where="worn"
		var plate: Dictionary=gear.plates[gear.plates.size()-1]
		plate.where="attached";plate.station="belt/0"
		var expected: float=.8+45.0*gear.LB_TO_KG
		check(is_equal_approx(game.carry_load.mass_for(1)-base,expected),"worn belt load not applied")
		for i in 3:await process_frame
		check(is_equal_approx(game.player.load_speed,game.carry_load.multiplier(1)),"player speed did not update")
		check(game.player.load_speed<1.0,"loaded belt did not slow player")
		check(is_equal_approx(game.session.carry_speed_guard.call(1),game.player.load_speed),"host and player calculated different speed")
	else:check(false,"could not enter gameplay")
	game.queue_free();await process_frame
	for failure in failures:push_error(failure)
	print("CARRY_LOAD_INTEGRATION ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
