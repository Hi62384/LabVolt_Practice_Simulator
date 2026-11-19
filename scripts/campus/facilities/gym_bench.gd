extends Node3D
## One articulated backrest, driven by the host's public exercise event.
var backrest: Node3D
var target_angle := 0.0
var occupant := 0

static func mount_offset() -> Vector3:
	return Vector3(0,0,.49)

static func position_for(exercise: String) -> String:
	if exercise in ["benchpress","chest_fly"]:return "flat"
	if exercise=="incline_press":return "incline"
	if exercise in ["chest_supported_row","reverse_fly"]:return "supported"
	if exercise=="overhead_extension":return "seated_free"
	return "seated"

static func backrest_angle(mode: String) -> float:
	return {"flat":0.0,"incline":.65,"supported":.80,"seated_free":.35,"seated":1.28}.get(mode,0.0)

# The frame faces +Z, and the adjustable pad runs toward -Z from its hinge.
# Align the body to that pad around the hips, independent of approach yaw.
static func body_pose(exercise: String, avatar_height: float, pad_angle: float=-1.0) -> Transform3D:
	var mode:=position_for(exercise)
	var angle:=backrest_angle(mode) if pad_angle<0.0 else pad_angle
	var hips:=Vector3(0,.59,0)
	var facing:=Basis.IDENTITY
	if mode in ["flat","incline"]:
		facing=Basis(Vector3.RIGHT,angle-PI*.5)
		hips=Vector3(0,.68,-.18)
	elif mode=="supported":
		facing=Basis(Vector3.UP,PI)*Basis(Vector3.RIGHT,PI*.5-angle)
		hips=Vector3(0,.67,-.12)
	return Transform3D(facing,hips-facing*Vector3.UP*.86*avatar_height)

static func approach_yaw(exercise: String) -> float:
	return 0.0 if position_for(exercise)=="supported" else PI

func build(standalone := false) -> void:
	var frame:=_material(Color("424f58"),.65,.5)
	var pad:=_material(Color("245666"),.82,0.0)
	var edge:=_material(Color("102f3c"),.8,0.0)
	if standalone:
		for x in [-.43,.43]:
			_part(self,Vector3(x,.25,0),Vector3(.10,.43,.11),frame)
			_part(self,Vector3(x,.075,0),Vector3(.16,.11,.61),frame)
		_part(self,Vector3(0,.47,0),Vector3(1.24,.12,.57),edge)
		_part(self,Vector3(0,.55,0),Vector3(1.18,.085,.53),pad)
		_collision(Vector3(1.24,.60,.63))
		set_process(false)
		return
	_part(self,Vector3(0,.27,0),Vector3(.13,.54,.12),frame)
	_part(self,Vector3(0,.08,-.63),Vector3(.85,.10,.20),frame)
	_part(self,Vector3(0,.08,.58),Vector3(.85,.10,.20),frame)
	_part(self,Vector3(0,.48,.49),Vector3(.61,.11,.63),edge)
	_part(self,Vector3(0,.54,.49),Vector3(.57,.09,.59),pad)
	backrest=Node3D.new();backrest.name="AdjustableBackrest";backrest.position=Vector3(0,.49,.16);add_child(backrest)
	_part(backrest,Vector3(0,0,-.60),Vector3(.64,.12,1.20),edge)
	_part(backrest,Vector3(0,.07,-.60),Vector3(.58,.08,1.15),pad)
	_collision(Vector3(.62,.55,1.8))
	set_process(false)

func _collision(size: Vector3) -> void:
	var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0;add_child(body)
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collision.shape=shape;collision.position.y=size.y*.5;body.add_child(collision)

func on_room_event(peer: int,event: Dictionary) -> void:
	if event.get("activity","") in ["exercise","trapped"] and event.get("station","")=="gym/benchpress":
		occupant=peer
		target_angle=backrest_angle(position_for(str(event.get("exercise",""))))
		set_process(true)
	elif peer==occupant and event.get("activity","") in ["idle","seat","emote"]:
		occupant=0;target_angle=0.0;set_process(true)

func _process(delta: float) -> void:
	backrest.rotation.x=move_toward(backrest.rotation.x,target_angle,delta*1.7)
	if is_equal_approx(backrest.rotation.x,target_angle):set_process(false)

func _part(parent: Node3D,at: Vector3,size: Vector3,material: Material) -> void:
	var mesh:=BoxMesh.new();mesh.size=size
	var part:=MeshInstance3D.new();part.mesh=mesh;part.material_override=material;part.position=at;parent.add_child(part)

func _material(color: Color,roughness: float,metallic: float) -> StandardMaterial3D:
	var result:=StandardMaterial3D.new();result.albedo_color=color;result.roughness=roughness;result.metallic=metallic;return result
