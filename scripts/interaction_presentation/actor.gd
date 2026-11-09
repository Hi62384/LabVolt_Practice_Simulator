extends Node
## One visual-only layer per avatar. Existing Idle/Walk/Seated player keeps running.
const Timeline = preload("res://scripts/interaction_presentation/timeline.gd")
var timeline = Timeline.new()
var arm: Node3D
var hand: Node3D
var rest = Transform3D.IDENTITY
var hand_local = Vector3(0,-0.48,0.012)
var last_applied = Transform3D.IDENTITY
var wrote_pose = false
var local_hand = false
var carrying_item := false

func _init() -> void:
	process_priority = 90
	set_process(false)

func bind_visual(visual: Node3D, first_person := false) -> bool:
	_restore()
	timeline.cancel()
	arm = null
	hand = null
	local_hand = first_person
	if is_instance_valid(visual):
		arm = visual.find_child("ArmR",true,false) as Node3D
		if visual.name == "ArmR":
			arm = visual
	if is_instance_valid(arm):
		hand = arm.find_child("Hand*",true,false) as Node3D
		rest = arm.transform
		if is_instance_valid(hand):
			hand_local = hand.position
	_refresh()
	return is_instance_valid(arm)

func apply_accepted(value: Dictionary) -> bool:
	if not is_instance_valid(arm):
		# Consume a valid watermark, then discard the unsupported transient. A later
		# rig replacement must not replay an event this actor could not present.
		timeline.accept(value)
		timeline.cancel()
		_refresh()
		return false
	var accepted: bool = timeline.accept(value)
	_refresh()
	return accepted

func reconcile_hold(value: Dictionary) -> void:
	timeline.reconcile_hold(value)
	_refresh()

func cancel() -> void:
	timeline.cancel()
	_restore()
	_refresh()

func reset() -> void:
	carrying_item=false
	timeline.reset()
	_restore()
	_refresh()

func set_enabled(value: bool) -> void:
	timeline.set_enabled(value)
	_refresh()

func set_suspended(value: bool) -> void:
	# Facility emote/exercise/food owns this arm until explicitly released.
	timeline.set_suspended(value)
	_refresh()

func hand_anchor(fallback: Transform3D) -> Transform3D:
	if not timeline.active() or not is_instance_valid(arm):
		return fallback
	var anchor = Transform3D(arm.global_basis,arm.to_global(hand_local))
	# Cosmetic endpoint displacement is bounded; no physics/reach source reads it.
	anchor.origin = fallback.origin + (anchor.origin-fallback.origin).limit_length(0.18)
	return anchor

func set_carrying_item(value: bool) -> void:
	if carrying_item==value:return
	carrying_item=value
	_refresh()

func _active() -> bool:
	return is_instance_valid(arm) and (timeline.active() or (local_hand and carrying_item and timeline.enabled and not timeline.suspended))

func _refresh() -> void:
	if not is_instance_valid(arm):
		timeline.cancel()
	var active := _active()
	if not active:
		_restore()
	if local_hand and is_instance_valid(arm):
		arm.visible = active
	set_process(active)

func _restore() -> void:
	if wrote_pose and is_instance_valid(arm) and arm.transform.is_equal_approx(last_applied):
		# Do not overwrite a facility pose or fresh AnimationPlayer result.
		arm.transform = rest
	wrote_pose = false

func _process(delta: float) -> void:
	timeline.advance(delta)
	if not _active():
		_refresh()
		return
	var pose: Dictionary = timeline.sample()
	# Rebuild from a fixed rest each frame: repeated knob actions cannot accumulate drift.
	var rotation = rest.basis.get_euler()
	rotation.x += -0.75 * float(pose["grip"]) if not local_hand else 0.0
	var reach = float(pose["reach"])
	if local_hand:
		# Camera-attached shoulder stays below view. Small reach/click motion,
		# rather than aiming the entire copied arm through the camera.
		rotation.x += 0.12*reach
	if not local_hand and reach > 0.0 and timeline.event.get("kind","") != "grasp":
		var target: Vector3 = timeline.event["target"]
		var direction = arm.get_parent_node_3d().to_local(target)-rest.origin
		if direction.length_squared() > 0.0001:
			# Independent straight toon arm: rotate local -Y toward target, never scale.
			var aimed = Quaternion(Vector3.DOWN,direction.normalized())
			rotation = Basis(rest.basis.get_rotation_quaternion().slerp(aimed,reach*0.85)).get_euler()
	rotation.y += float(pose["twist"])
	arm.transform = Transform3D(Basis.from_euler(rotation).scaled(rest.basis.get_scale()),rest.origin)
	last_applied = arm.transform
	wrote_pose = true
	if local_hand and carrying_item:
		arm.visible=true
	elif local_hand:
		# The camera-mounted copy has no collider. Suppress it when a wall sits
		# between the camera and the animated hand, instead of drawing through it.
		var camera := arm.get_parent() as Camera3D
		if is_instance_valid(camera):
			var ray := PhysicsRayQueryParameters3D.create(camera.global_position,
				arm.to_global(hand_local), 1)
			arm.visible = camera.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _exit_tree() -> void:
	_restore()
