extends SceneTree
const Mass=preload("res://scripts/campus/facilities/carry_mass.gd")
const Gym=preload("res://scripts/campus/facilities/gym_progress.gd")
const Session=preload("res://scripts/session.gd")
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:failures.append(message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var profile:={"dorm":{"carry_items":["notebook","bag:a","kit:k"],"worn_supplies":{"head":"lab_goggles"},"carried_components":[{"type":"led"}],"backpacks":{"a":{"size":"backpack_small","location":"hotbar","items":[{"kind":"bag","id":"b"},{"kind":"kit","id":"k"}]},"b":{"size":"backpack_medium","location":"nested","items":[{"kind":"supply","id":"flashlight"},{"kind":"bag","id":"a"}]} }},"kits":{"k":{"items":{"led":10},"board":{"parts":[],"wires":[]}}}}
	var expected:=.30+.55+.80+.25+.40+.22+.02+.08+.002
	check(is_equal_approx(Mass.profile_mass(profile),expected),"nested mass or identity deduplication wrong")
	var dumbbells:=[{"owner":1,"where":"held","lb":10.0}]
	var bars:={"gym/benchpress":{"owner":1,"where":"stowed"}}
	var belts:=[{"owner":1,"where":"worn"}]
	var plates:=[{"station":"gym/benchpress","owner":0,"where":"attached","lb":45.0},{"station":"belt/0","owner":0,"where":"attached","lb":10.0},{"station":"","owner":1,"where":"held","lb":5.0},{"station":"","owner":2,"where":"held","lb":45.0}]
	var gym_mass: float=20.0*Mass.LB_TO_KG+20.0+.8+60.0*Mass.LB_TO_KG
	check(is_equal_approx(Mass.gym_mass(1,dumbbells,bars,belts,plates),gym_mass),"gym load omitted or double counted a plate")
	check(is_equal_approx(Mass.speed_multiplier(5,0),1.0),"light inventory slowed movement")
	check(Mass.speed_multiplier(100,0)<Mass.speed_multiplier(50,0),"heavy inventory did not slow progressively")
	check(Mass.speed_multiplier(100,1)>Mass.speed_multiplier(100,0),"strength did not increase carrying capacity")
	check(Mass.speed_multiplier(100000,0)>=.20,"heavy load could immobilize player")
	var muscles:={"biceps":{"strength":1.0,"size":0.0}}
	check(is_zero_approx(Gym.overall_strength({"muscles":muscles})),"overall strength did not use muscle size")
	var baseline: float=Gym.body_mass({})
	var heavier: float=Gym.body_mass({"avatar_cosmetics":{"body":{"height":1.1,"width":1.2}}})
	check(is_equal_approx(baseline,70.0) and heavier>baseline,"saved body proportions did not change body mass")
	check(Gym.effective_load("pullup",0,heavier)>Gym.effective_load("pullup",0,baseline),"body mass did not affect bodyweight load")
	check(is_equal_approx(Gym.effective_load("benchpress",20,heavier),Gym.effective_load("benchpress",20,baseline)),"body mass changed a bench press load")
	check(is_equal_approx(Gym.effective_load("pullup",10,baseline)-Gym.effective_load("pullup",0,baseline),10.0),"external weight was omitted")
	var session=Session.new();root.add_child(session);session.campus_enabled=true
	session.roster={1:{}};session.poses={1:{"position":Vector3(0,0,1)}};session.last_pose={1:Time.get_ticks_msec()-500}
	session.carry_speed_guard=func(_peer):return .5
	session.accept_pose(1,{"position":Vector3(4,0,1),"yaw":0.0,"pitch":0.0})
	check(session.poses[1].position.x<2.0,"host ignored movement load limit")
	session.free()
	for failure in failures:push_error(failure)
	print("CARRY_MASS ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
