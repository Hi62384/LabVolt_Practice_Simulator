extends CharacterBody3D
const SafeRecovery = preload("res://scripts/campus/presentation/navigation_safety/safe_recovery.gd")
const DEFAULT_KEYS := {"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D,
	"sprint": KEY_SHIFT, "crouch": KEY_CTRL, "jump": KEY_SPACE, "interact": KEY_E,
	"inventory": KEY_TAB, "kits": KEY_K, "read_sheet": KEY_N, "drop_lead": KEY_G, "emotes": KEY_H,
	"slot_1": KEY_1, "slot_2": KEY_2, "slot_3": KEY_3, "slot_4": KEY_4, "slot_5": KEY_5, "slot_6": KEY_6}
var safe_recovery = SafeRecovery.new(Vector3(13,0.05,-18))
var facility_movement_locked: Callable
var load_speed := 1.0
var facility_seat := {}
var inspecting := false
var resting := false
var rest_anchor := Transform3D.IDENTITY
var seated: CharacterBody3D
var seated_look = preload("res://scripts/campus/seating/chair_controls/look_state.gd").new()
var chair_entry_position := Vector3.ZERO
var sensitivity := 0.00225
var enabled := false
var head_bob := false
var invert_vertical := false
var invert_horizontal := false
var reduced_motion := false
var eyes: Camera3D
var yaw_target := 0.0
var pitch_target := 0.0
var crouched := false
var clock := 0.0
var keys := DEFAULT_KEYS.duplicate()
var collider: CollisionShape3D

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	collider = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.25
	capsule.height = 1.7
	collider.shape = capsule
	collider.position.y = 0.85
	add_child(collider)
	eyes = Camera3D.new()
	eyes.position.y = 1.65
	eyes.fov = 72
	eyes.near = 0.035
	eyes.current = true
	add_child(eyes)
	load_settings()

func down(action: String) -> bool:
	return enabled and Input.is_physical_key_pressed(keys[action])

func look(relative: Vector2) -> void:
	var horizontal := relative.x*sensitivity if invert_horizontal else -relative.x*sensitivity
	if is_instance_valid(seated):
		seated_look.look(horizontal, not seated.fixed_seat and down("crouch"))
		yaw_target = seated_look.chair_turn
	else:
		yaw_target += horizontal
	pitch_target = clampf(pitch_target+relative.y*sensitivity*(1 if invert_vertical else -1),-1.46,1.46)

func begin_rest(anchor: Transform3D) -> bool:
	if seated!=null or inspecting or not anchor.is_finite():return false
	resting=true;rest_anchor=anchor;velocity=Vector3.ZERO
	collider.set_deferred("disabled",true)
	global_position=anchor.origin;eyes.position.y=.12
	return true

func end_rest(destination: Vector3) -> void:
	resting=false;global_position=destination;velocity=Vector3.ZERO
	crouched=false;(collider.shape as CapsuleShape3D).height=1.7;collider.position.y=.85
	collider.set_deferred("disabled",false);eyes.position.y=1.65

func _physics_process(delta: float) -> void:
	if resting:
		global_position=rest_anchor.origin;velocity=Vector3.ZERO
		rotation.y=lerp_angle(rotation.y,yaw_target,1-exp(-25*delta))
		eyes.rotation.x=pitch_target
		return
	if facility_movement_locked.is_valid() and facility_movement_locked.call():
		rotation.y=lerp_angle(rotation.y,yaw_target,1-exp(-25*delta))
		eyes.rotation.x=lerpf(eyes.rotation.x,pitch_target,1-exp(-25*delta))
		if facility_seat.has("seat_position"):
			var seat_position: Vector3 = facility_seat.seat_position
			eyes.position = to_local(seat_position + Vector3.UP * 1.16)
		velocity=Vector3.ZERO;return
	if inspecting:velocity=Vector3.ZERO;return
	if is_instance_valid(seated):
		global_position=seated.global_position
		rotation.y=seated_look.world_yaw(seated.fixed_yaw if seated.fixed_seat else seated.swivel.rotation.y)
		eyes.rotation.x=lerpf(eyes.rotation.x,pitch_target,1-exp(-25*delta))
		eyes.position.y=lerpf(eyes.position.y,1.16,1-exp(-16*delta))
		velocity=Vector3.ZERO
		return
	clock += delta
	rotation.y = lerp_angle(rotation.y,yaw_target,1-exp(-25*delta))
	eyes.rotation.x = lerpf(eyes.rotation.x,pitch_target,1-exp(-25*delta))
	var wants_crouch := down("crouch")
	if crouched and not wants_crouch:
		var query := PhysicsRayQueryParameters3D.create(global_position+Vector3.UP,global_position+Vector3.UP*1.8,1)
		wants_crouch = not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	crouched = wants_crouch
	(collider.shape as CapsuleShape3D).height = 1.0 if crouched else 1.7
	collider.position.y = 0.5 if crouched else 0.85
	var wish := Vector2(float(down("right"))-float(down("left")),float(down("back"))-float(down("forward"))).normalized()
	var direction := basis * Vector3(wish.x,0,wish.y)
	var speed := (1.4 if crouched else (6.4 if down("sprint") else 3.2))*load_speed
	velocity.x = move_toward(velocity.x,direction.x*speed,14*delta)
	velocity.z = move_toward(velocity.z,direction.z*speed,14*delta)
	if not is_on_floor():
		velocity.y -= 9.8*delta
	elif down("jump") and not crouched:
		velocity.y = 4.4
	else:
		velocity.y = 0
	move_and_slide()
	# Only the owning peer's movement is corrected; normal pose replication follows.
	if is_on_floor() and not is_instance_valid(seated):
		safe_recovery.observe_grounded(global_position)
	if safe_recovery.needs_recovery(global_position):
		global_position=safe_recovery.recovery_position()
		velocity=Vector3.ZERO
	var bob := sin(clock*11)*0.025 if head_bob and not reduced_motion and is_on_floor() and wish.length()>0 else 0.0
	eyes.position.y = lerpf(eyes.position.y,(0.95 if crouched else 1.65)+bob,1-exp(-16*delta))

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls","sensitivity",sensitivity)
	cfg.set_value("controls","head_bob",head_bob)
	cfg.set_value("controls","invert_vertical",invert_vertical)
	cfg.set_value("controls","invert_horizontal",invert_horizontal)
	for action in keys:
		cfg.set_value("keys",action,keys[action])
	cfg.save("user://settings.cfg")

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") != OK:
		return
	sensitivity = clampf(cfg.get_value("controls","sensitivity",sensitivity),0.0003,0.008)
	head_bob = bool(cfg.get_value("controls","head_bob",false))
	invert_vertical = bool(cfg.get_value("controls","invert_vertical",false))
	invert_horizontal = bool(cfg.get_value("controls","invert_horizontal",false))
	for action in keys:
		var key: Variant = cfg.get_value("keys",action,keys[action])
		if key is int and key > 0 and key not in [KEY_ESCAPE, KEY_F11]:
			keys[action] = key

func sit(chair: CharacterBody3D) -> void:
	if resting or seated!=null or chair.rider!=null:
		return
	chair_entry_position=global_position
	seated=chair
	chair.rider=self
	chair.swivel.rotation.y=chair.fixed_yaw if chair.fixed_seat else rotation.y
	if chair.fixed_seat:pitch_target=0.0
	seated_look.enter(chair.swivel.rotation.y)
	yaw_target=seated_look.chair_turn
	chair.previous_turn_target=yaw_target
	chair.turn_target=yaw_target
	collider.disabled=true

func set_facility_seat(event: Dictionary) -> void:
	if event.has("seat_position"):
		facility_seat = event.duplicate()
		yaw_target = float(event.seat_yaw)
		rotation.y = yaw_target
		pitch_target = 0.0
	elif not facility_seat.is_empty():
		facility_seat.clear()
		eyes.position = Vector3(0, 1.65, 0)

func stand_up() -> void:
	if not is_instance_valid(seated):
		return
	var candidates: Array[Vector3]=[]
	if chair_entry_position.distance_to(seated.global_position)<3.0:
		candidates.append(chair_entry_position)
	var radii := [0.65,0.8,1.1,1.5,2.0,2.5,3.0] if seated.fixed_seat else [0.8,1.1,1.5,2.0]
	for radius in radii:
		for step in range(16):
			var angle := TAU*float(step)/16.0
			candidates.append(seated.global_position+Vector3(sin(angle)*radius,0,cos(angle)*radius))
	var standing_shape := CapsuleShape3D.new()
	standing_shape.radius=.25
	standing_shape.height=1.7
	for candidate in candidates:
		var floor_query := PhysicsRayQueryParameters3D.create(candidate+Vector3.UP*0.4,candidate-Vector3.UP*1.4,1,[get_rid(),seated.get_rid()])
		var floor_hit := get_world_3d().direct_space_state.intersect_ray(floor_query)
		if floor_hit.is_empty() or floor_hit.normal.dot(Vector3.UP)<0.7:
			continue
		var destination: Vector3=floor_hit.position+Vector3.UP*0.03
		if not seated.fixed_seat and not SafeRecovery.is_known_walkable(destination):
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape=standing_shape
		query.transform=Transform3D(Basis.IDENTITY,destination+Vector3(0,.85,0))
		query.collision_mask=1
		query.exclude=[get_rid(),seated.get_rid()]
		if get_world_3d().direct_space_state.intersect_shape(query,8).is_empty():
			yaw_target=seated_look.leave(seated.fixed_yaw if seated.fixed_seat else seated.swivel.rotation.y)
			rotation.y=yaw_target
			seated.rider=null
			seated=null
			global_position=destination
			(collider.shape as CapsuleShape3D).height=1.7
			collider.position.y=.85
			collider.disabled=false
			return
