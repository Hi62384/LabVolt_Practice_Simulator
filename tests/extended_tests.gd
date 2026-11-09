extends SceneTree
var game: Node
var failures := 0
var count := 0
func check(value: bool,label: String) -> void:
	count+=1
	if not value:
		failures+=1
		printerr("FAIL: "+label)
func wait(t: float) -> void:
	await create_timer(t).timeout
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	await wait(.3)
	check(game.session.labs.size()==3,"three independent circuit states")
	check(game.chairs.size()>=7 and game.chairs.all(func(chair):return chair.get_script()==preload("res://scripts/rolling_chair.gd")),"original and added classroom chairs all roll")
	for n in range(3):
		var state=game.session.labs[n]
		var pos: Vector3=state.positions.storage
		check(state.act(1,{"op":"pickup"},pos)!="","closed drawer prevents pickup")
		check(state.act(1,{"op":"drawer"},pos)=="","drawer opens at every bench")
		for i in range(12):
			state.act(1,{"op":"pickup","color":i%4},pos)
			check(state.act(1,{"op":"plug","port":"P_A"},state.positions.P_A)=="","stack slot %d at bench %d"%[i+1,n])
			state.act(1,{"op":"return"},pos)
		state.act(1,{"op":"pickup"},pos)
		check(state.act(1,{"op":"plug","port":"P_A"},state.positions.P_A).contains("12"),"thirteenth plug rejected")
		state.act(1,{"op":"discard"},pos)
		check(state.cables.size()==12,"discard held cable only")
		state.act(1,{"op":"unplug","port":"P_A"},state.positions.P_A)
		state.act(1,{"op":"discard"},pos)
		check(state.cables.size()==11,"unplug and return installed cable")
	game.session.broadcast()
	await wait(.2)
	check(game.leads.size()==33,"renders cables from all three benches")
	var before: int=game.session.labs[0].revision
	game.session.poses[1]={"position":game.session.labs[1].positions.R_0}
	game.session.last_actions.clear()
	game.session.apply_action(1,{"op":"switch","station":1,"kind":"R","index":0,"expected":false})
	check(game.session.labs[1].switches.R[0] and game.session.labs[0].revision==before,"side bench switch isolated and routed")
	var chair=game.chairs[0]
	chair.position=Vector3(0,0,4)
	chair.occupant=42
	chair.drive=Vector2(0,-1)
	chair.turn_target=0
	await wait(.5)
	# Direct physical acceleration; refresh after ownership cleanup.
	chair.occupant=1
	game.session.roster[42]={"name":"test","ready":false}
	game.session.poses[1]={"position":chair.position}
	game.player.position=chair.position+Vector3(0,0,1)
	chair.occupant=0
	game._claim_chair(1,0)
	check(game.player.seated==chair and chair.occupant==1,"sit claims chair")
	game._claim_chair(42,0)
	check(chair.occupant==1,"second player cannot claim occupied chair")
	game.player.yaw_target=1.2
	await wait(1.5)
	check(chair.swivel.rotation.y>.3,"seated turn rotates swivel")
	check(game.camera.position.y<1.3,"seated eye height")
	game._stand_from_chair()
	check(game.player.seated==null and chair.occupant==0,"stand releases ownership")
	game.session.roster.erase(42)
	var state=game.session.labs[0]
	state.act(1,{"op":"pickup"},state.positions.storage)
	game.session.broadcast()
	await wait(.1)
	var held=state.holding(1)
	var mesh=game.carry_visuals[held.id].mesh
	var old: Vector3=game.carry_visuals[held.id].b
	game.camera.rotation.x=.2
	await process_frame
	await process_frame
	check(game.carry_visuals[held.id].mesh==mesh,"held cable retains visual node")
	check(game.carry_visuals[held.id].b!=old,"held cable follows render frame camera")
	check(game.sfx.bank.size()>=11,"distinct sound bank generated")
	print("EXTENDED: %d checks, %d failures"%[count,failures])
	quit(1 if failures else 0)
