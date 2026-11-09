extends Node3D
## Cosmetic only. Parent this beside the avatar; bind_visual(toon_or_imported_visual).
## Never changes player root, collision, camera, authoritative pose, or movement speed.
var visual: Node3D
var original := Transform3D.IDENTITY
var arms:={}
var state:={}
var elapsed:=0.0
var food: Node3D

func bind_visual(node: Node3D) -> void:
	restore()
	visual=node;original=node.transform;arms.clear()
	set_process(false)
	for name in ["ArmL","ArmR"]:
		var arm:=visual.find_child(name,true,false) as Node3D
		if arm:arms[name]={"node":arm,"transform":arm.transform}

func apply_event(value: Dictionary, show_food: bool) -> void:
	if show_food:
		if value.has("held"):
			set_food(value.held)
		elif value.get("activity","")=="holding":
			set_food({"item":value.get("item",""),"station":""})
	if value.get("activity","") in ["holding","consume","place","pickup"]:return
	restore()
	state=value.duplicate(true);elapsed=0
	set_process(not state.get("activity","idle") in ["idle",""])

func set_food(held: Dictionary) -> void:
	if is_instance_valid(food):food.queue_free()
	food=null
	if not is_instance_valid(visual) or held.is_empty() or str(held.get("station",""))!="":return
	food=preload("res://scripts/campus/facilities/food_visual.gd").build(str(held.item),int(held.get("servings",4)))
	food.name="FacilityFood";visual.add_child(food)
	food.position=Vector3(0.35,.98,-0.3)

func restore() -> void:
	if is_instance_valid(visual) and visual.has_meta(&"dorm_rest_pose"):return
	if is_instance_valid(visual):visual.transform=original
	for arm in arms.values():
		if is_instance_valid(arm.node):arm.node.transform=arm.transform

func _process(delta: float) -> void:
	if is_instance_valid(visual) and visual.has_meta(&"dorm_rest_pose"):return
	if not is_instance_valid(visual):set_process(false);return
	elapsed+=delta
	if state.get("activity","")=="emote":
		var emote:=str(state.get("emote","wave"))
		if elapsed*1000>int(state.get("duration_ms",1800)):
			restore();set_process(false);return
		for key in arms:
			if emote=="wave" and key!="ArmR":continue
			var arm: Node3D=arms[key].node
			arm.transform=arms[key].transform
			arm.rotation.z+=(1 if key=="ArmR" else -1)*(2.2+sin(elapsed*8)*0.22)
		# Imported visuals may lack named arm nodes: a small stationary torso turn is visible.
		if arms.is_empty():visual.rotation.y=original.basis.get_euler().y+sin(elapsed*8)*0.1
	elif state.get("activity","")=="exercise":
		var phase:=float(state.get("phase",0))
		var kind:=str(state.get("exercise",""))
		var target:=original
		# Bounded cosmetic offsets, never a new world position or traversal capability.
		if kind=="pushup":target.basis=original.basis.rotated(Vector3.RIGHT,-1.1);target.origin.y-=0.5+phase*0.12
		elif kind=="squat":target.origin.y-=phase*0.3
		elif kind=="pullup":target.origin.y+=phase*0.2
		elif kind=="benchpress":target.basis=original.basis.rotated(Vector3.RIGHT,-0.8)
		visual.transform=visual.transform.interpolate_with(target,minf(delta*12,1))
		for arm in arms.values():
			arm.node.transform=arm.transform
			arm.node.rotation.x=-phase*1.0
	elif state.get("activity","")=="seat":
		visual.position=original.origin+Vector3(0,-0.3,0)
		if state.has("seat_position"):
			visual.global_position=state.seat_position+Vector3.DOWN*.3
			visual.global_rotation.y=float(state.seat_yaw)

func _exit_tree() -> void:restore()
