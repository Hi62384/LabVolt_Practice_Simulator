extends SceneTree
const Gear=preload("res://scripts/campus/facilities/gym_barbells.gd")
const Motion=preload("res://scripts/campus/presentation/decor/m105/gym_equipment_motion.gd")
class Services:
	var gym_motion: Node
class Game extends Node:
	var campus_services=Services.new()
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var motion=Motion.new();root.add_child(motion)
	var game=Game.new();root.add_child(game);game.campus_services.gym_motion=motion
	var gear=Gear.new();root.add_child(gear);gear.set_process(false);gear.game=game;gear._reset_plates()
	var station:="gym/benchpress"
	gear.bars[station].where="held";gear.bars[station].owner=1
	gear.plates[0].where="attached";gear.plates[0].station=station;gear.plates[0].side=-1;gear.plates[0].order=1
	var event:={"activity":"exercise","station":station,"exercise":"benchpress","equipment":"barbell","phase":1,"weight":25.0}
	motion.on_room_event(1,event);gear._room_event(1,event)
	for i in 60:motion._process(.02)
	gear._sync_bench_models()
	var ok: bool=gear.bench_models.has(1)
	if ok:
		var visual: Node3D=gear.bench_models[1].visual
		ok=visual.get_child_count()==2 and visual.global_position.distance_to(motion.bars[station].global_position)<.001
	var trap:={"activity":"trapped","station":station,"exercise":"benchpress","equipment":"barbell","progress":.5}
	motion.on_room_event(1,trap);gear._room_event(1,trap)
	for i in 60:motion._process(.02)
	gear._sync_bench_models()
	ok=ok and gear.bench_models.has(1) and gear.bench_models[1].visual.global_position.distance_to(motion.bars[station].global_position)<.001
	gear._room_event(1,{"activity":"idle"});gear._sync_bench_models()
	ok=ok and gear.bench_models.is_empty()
	if not ok:push_error("Carried loaded bar did not follow the bench and rescue motion")
	print("CARRIED_BENCH_VISUAL ","PASS" if ok else "FAIL")
	gear.free();game.free();motion.free();quit(0 if ok else 1)
