extends RefCounted

const Configuration = preload("res://scripts/campus/items/equipment_configuration.gd")

static func build(parent: Node3D, layers := 1) -> MeshInstance3D:
	var shell := _box(parent,Vector3.ZERO,Vector3(.105,.195,.012),Color("243943"),layers)
	var speaker := _box(parent,Vector3(0,.088,.007),Vector3(.024,.003,.002),Color("7597a3"),layers)
	var power := _box(parent,Vector3(.053,.046,0),Vector3(.004,.024,.004),Color("7597a3"),layers)
	var quad := QuadMesh.new()
	quad.size = Vector2(.094,.156)
	var screen := _mesh(parent,quad,Vector3(0,.004,.007),Color("080f14"),layers)
	screen.material_override.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var button := CylinderMesh.new()
	button.top_radius=.005
	button.bottom_radius=.005
	button.height=.001
	var home := _mesh(parent,button,Vector3(0,-.087,.007),Color("7597a3"),layers)
	home.rotation.x=PI/2
	parent.set_meta("phone_shell",shell)
	parent.set_meta("phone_trim",[speaker,power,home])
	return screen

static func apply_appearance(parent: Node3D, appearance: Dictionary) -> void:
	var shell: MeshInstance3D=parent.get_meta("phone_shell")
	var config: Dictionary={"appearance":appearance}
	var finish: Vector2=Configuration.value(Configuration.PHONE,config,"appearance","finish",Vector2(.45,0))
	shell.material_override.albedo_color=Color(Configuration.value(Configuration.PHONE,config,"appearance","shell","243943"))
	shell.material_override.roughness=finish.x
	shell.material_override.metallic=finish.y
	var trim:=Color(Configuration.value(Configuration.PHONE,config,"appearance","trim","7597a3"))
	for part in parent.get_meta("phone_trim"):
		part.material_override.albedo_color=trim
	preload("res://scripts/campus/items/decoration_surface.gd").attach(parent,appearance.get("decoration",[]),Vector3(0,-.019,-.0064),Vector3(0,PI,0),Vector2(.087,.131),shell.layers)

static func _box(parent: Node3D, offset: Vector3, size: Vector3, color: Color, layers: int) -> MeshInstance3D:
	var mesh:=BoxMesh.new()
	mesh.size=size
	return _mesh(parent,mesh,offset,color,layers)

static func _mesh(parent: Node3D, mesh: Mesh, offset: Vector3, color: Color, layers: int) -> MeshInstance3D:
	var instance:=MeshInstance3D.new()
	instance.mesh=mesh
	instance.position=offset
	instance.layers=layers
	instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material:=StandardMaterial3D.new()
	material.albedo_color=color
	material.roughness=.45
	instance.material_override=material
	parent.add_child(instance)
	return instance
