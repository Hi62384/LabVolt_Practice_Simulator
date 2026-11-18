extends SceneTree

const Weights = preload("res://scripts/campus/facilities/gym_weights.gd")
const Barbells = preload("res://scripts/campus/facilities/gym_barbells.gd")
const Decor = preload("res://scripts/campus/presentation/decor/m105/m105_decor.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var expected := []
	for i in range(1,13):expected.append(i*2.5)
	for i in range(7,21):expected.append(i*5.0)
	for i in range(11,21):expected.append(i*10.0)
	assert(Weights.SIZES.size() == 36 and Weights.RACK_SLOTS == 36)
	assert(expected.all(func(lb):return lb in Weights.SIZES))
	var weights := Weights.new()
	root.add_child(weights)
	weights._build_rack()
	var bar := Barbells.new()
	root.add_child(bar)
	bar._reset_plates()
	bar._build_rack()
	for index in Barbells.SIZES.size():
		assert(bar._rack_count(index) == Barbells.COUNTS[index])
	var rods := _with_role(bar, "gym_plate_rod")
	assert(rods.size() == Barbells.SIZES.size())
	assert(Barbells.PLATE_GAP > .086)
	var stage := Node3D.new()
	root.add_child(stage)
	var decor := Decor.new()
	stage.add_child(decor)
	assert(decor.mount(stage))
	var lockers := _with_role(stage, "gym_progress")
	assert(lockers.size() == 6)
	await physics_frame
	await physics_frame
	var physics := stage.get_world_3d().direct_space_state
	for locker in lockers:
		var center: Vector3 = locker.global_position
		var ray := PhysicsRayQueryParameters3D.create(center+Vector3.RIGHT*1.3,center-Vector3.RIGHT*.15,4)
		assert(physics.intersect_ray(ray).get("collider") == locker)
	for slot in Weights.RACK_SLOTS:
		var bottom := weights._slot_position(slot)-Vector3.UP*weights._radius(Weights.SIZES[weights.rack_order[slot]])
		var ray := PhysicsRayQueryParameters3D.create(bottom+Vector3.UP*.015,bottom-Vector3.UP*.02,1)
		var hit := physics.intersect_ray(ray)
		assert(not hit.is_empty() and hit.collider == weights.rack_frame and is_equal_approx(hit.position.y,bottom.y))
	var machine = preload("res://scripts/campus/facilities/gym_cable_machine.gd").new()
	stage.add_child(machine)
	machine.position = Vector3(15,0,33)
	machine.build("gym/cable_test")
	await physics_frame
	await physics_frame
	for pin in machine.pin_targets:
		var pin_point: Vector3 = pin.global_position
		var ray := PhysicsRayQueryParameters3D.create(pin_point+Vector3.BACK*1.4,pin_point+Vector3.FORWARD*.1,4)
		assert(physics.intersect_ray(ray).get("collider") == pin)
		assert(int(pin.get_meta("weight")) % 5 == 0)
	print("GYM_STORAGE PASS")
	quit()

func _with_role(node: Node, role: String) -> Array:
	return node.find_children("*","StaticBody3D",true,false).filter(func(body):return body.get_meta("role","")==role)
