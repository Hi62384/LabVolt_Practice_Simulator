extends Node3D
## One articulated backrest, driven by the host's public exercise event.
var backrest: Node3D
var target_angle := 0.0
var occupant := 0

static func position_for(exercise: String) -> String:
	if exercise in ["benchpress","chest_fly"]:return "flat"
	if exercise=="incline_press":return "incline"
	if exercise in ["chest_supported_row","reverse_fly"]:return "supported"
	if exercise=="overhead_extension":return "seated_free"
	return "seated"

func build() -> void:
	var frame:=_material(Color("424f58"),.65,.5)
	var pad:=_material(Color("245666"),.82,0.0)
	var edge:=_material(Color("102f3c"),.8,0.0)
	_part(self,Vector3(0,.27,0),Vector3(.13,.54,.12),frame)
	_part(self,Vector3(0,.08,-.63),Vector3(.85,.10,.20),frame)
	_part(self,Vector3(0,.08,.58),Vector3(.85,.10,.20),frame)
	_part(self,Vector3(0,.48,.49),Vector3(.61,.11,.63),edge)
	_part(self,Vector3(0,.54,.49),Vector3(.57,.09,.59),pad)
	backrest=Node3D.new();backrest.name="AdjustableBackrest";backrest.position=Vector3(0,.49,.16);add_child(backrest)
	_part(backrest,Vector3(0,0,-.60),Vector3(.64,.12,1.20),edge)
	_part(backrest,Vector3(0,.07,-.60),Vector3(.58,.08,1.15),pad)
	var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0;add_child(body)
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(.62,.55,1.8);collision.shape=shape;collision.position.y=.275;body.add_child(collision)
	set_process(false)

func on_room_event(peer: int,event: Dictionary) -> void:
	if event.get("activity","") in ["exercise","trapped"] and event.get("station","")=="gym/benchpress":
		occupant=peer
		match position_for(str(event.get("exercise",""))):
			"flat":target_angle=0.0
			"incline":target_angle=.65
			"supported":target_angle=.80
			"seated_free":target_angle=.35
			_:target_angle=1.28
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
