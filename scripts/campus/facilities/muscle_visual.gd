extends RefCounted
## Deform fitted meshes in their limb-local coordinates, preserving the rig.
const Warp=preload("res://scripts/avatar_cosmetics/body_deformation/mesh_warp.gd")
const Gym=preload("res://scripts/campus/facilities/gym_progress.gd")
const ORIGINAL:=&"gym_original_mesh"

static func apply(avatar: Node3D,raw: Dictionary) -> void:
	if not is_instance_valid(avatar):return
	var sizes:={}
	for name in Gym.MUSCLE_GROUPS:
		var value: Variant=raw.get(name,0.0)
		sizes[name]=clampf(float(value),0.0,1.0) if (value is int or value is float) and is_finite(float(value)) else 0.0
	if sizes.values().all(func(value):return value==0.0):
		for mesh in avatar.find_children("*","MeshInstance3D",true,false):
			if mesh.has_meta(ORIGINAL):mesh.mesh=mesh.get_meta(ORIGINAL)
		return
	var body:=avatar.get_node_or_null("Body") as Node3D
	if body!=null:
		for child in body.get_children():
			if child is Node3D and child.name not in ["Head","Neck","ArmL","ArmR"]:
				_deform(child,func(v: Vector3):return _torso(v,sizes))
		for side in ["L","R"]:
			var arm:=body.get_node_or_null("Arm"+side) as Node3D
			if arm!=null:
				for child in arm.get_children():
					if child is Node3D and (str(child.name).begins_with("Sleeve") or str(child.name).begins_with("Forearm") or str(child.name).begins_with("VisibleForearm") or str(child.name).begins_with("Cuff")):
						_deform(child,func(v: Vector3):return _arm(v,sizes))
	for side in ["L","R"]:
		var leg:=avatar.get_node_or_null("Leg"+side) as Node3D
		if leg==null:continue
		for child in leg.get_children():
			if child is Node3D and (str(child.name).begins_with("Trouser") or str(child.name).begins_with("Calf") or str(child.name).begins_with("Leg")):
				_deform(child,func(v: Vector3):return _leg(v,sizes))

static func _deform(node: Node3D,mapping: Callable) -> void:
	var meshes: Array=[]
	if node is MeshInstance3D:meshes.append(node)
	meshes.append_array(node.find_children("*","MeshInstance3D",true,false))
	for mesh in meshes:
		if not mesh.has_meta(ORIGINAL):mesh.set_meta(ORIGINAL,mesh.mesh)
		else:mesh.mesh=mesh.get_meta(ORIGINAL)
	Warp.deform_tree(node,mapping)

static func _bell(value: float,center: float,width: float) -> float:
	return exp(-pow((value-center)/width,2.0))
static func _arm(v: Vector3,s: Dictionary) -> Vector3:
	var upper:=_bell(v.y,-.13,.13);var lower:=_bell(v.y,-.30,.10);var shoulder:=_bell(v.y,-.04,.075)
	var radial:=1.0+.12*upper*(float(s.biceps)+float(s.triceps))*.5+.12*lower*float(s.forearms)+.10*shoulder*float(s.side_deltoids)
	var front:=maxf(0.0,v.z)*upper*.07*float(s.biceps)-maxf(0.0,-v.z)*upper*.07*float(s.triceps)
	var delt:=shoulder*(maxf(0.0,v.z)*float(s.front_deltoids)-maxf(0.0,-v.z)*float(s.rear_deltoids))*.08
	return Vector3(v.x*radial,v.y,v.z*radial+front+delt)
static func _leg(v: Vector3,s: Dictionary) -> Vector3:
	var thigh:=_bell(v.y,-.18,.18);var calf:=_bell(v.y,-.54,.12);var hip:=_bell(v.y,-.06,.10)
	var radial:=1.0+.11*thigh*(float(s.quadriceps)+float(s.hamstrings))*.5+.12*calf*float(s.calves)+.06*hip*float(s.glutes)
	var depth:=maxf(0.0,v.z)*thigh*.08*float(s.quadriceps)-maxf(0.0,-v.z)*(thigh*.08*float(s.hamstrings)+hip*.08*float(s.glutes))
	return Vector3(v.x*radial,v.y,v.z*radial+depth)
static func _torso(v: Vector3,s: Dictionary) -> Vector3:
	var chest:=_bell(v.y,1.14,.13);var mid:=_bell(v.y,.98,.12);var shoulder:=_bell(v.y,1.25,.085)
	var width:=1.0+.08*chest*float(s.lats)+.06*shoulder*(float(s.side_deltoids)+float(s.trapezius))*.5
	var forward:=maxf(0.0,v.z)*(.10*chest*float(s.chest)+.05*mid*float(s.abdominals))
	var back:=maxf(0.0,-v.z)*(.09*chest*float(s.lats)+.05*mid*float(s.lower_back)+.04*shoulder*float(s.trapezius))
	return Vector3(v.x*width,v.y,v.z+forward-back)
