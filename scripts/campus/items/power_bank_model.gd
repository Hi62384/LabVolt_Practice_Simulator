extends RefCounted

const Config = preload("res://scripts/campus/items/equipment_configuration.gd")
const Finish = preload("res://scripts/campus/items/equipment_finish.gd")

static func dimensions(options: Dictionary) -> Vector3:
	var capacity: float=Config.value(Config.POWER_BANK,options,"hardware","capacity",10.0)
	var size:=clampf((capacity-10.0)/22.0,0.0,1.0)
	return Vector3(lerpf(.076,.106,size),lerpf(.022,.038,size),lerpf(.122,.169,size))

static func build(parent: Node3D, options: Dictionary, percent: int) -> Node3D:
	var bank := Node3D.new()
	parent.add_child(bank)
	var size := dimensions(options)
	var side := _box(bank,Vector3(0,size.y*.48,0),size,Color("667b84"))
	var face := _box(bank,Vector3(0,size.y,-.001),Vector3(size.x*.9,.003,size.z*.90),Color("b7c2ca"))
	bank.set_meta("equipment_shell",[side])
	bank.set_meta("equipment_trim",[face])
	bank.set_meta("decoration_anchor",{"part":bank,"position":Vector3(0,size.y+.002,size.z*.19),"rotation":Vector3(-PI/2,0,0),"area":Vector2(size.x*.77,size.z*.40)})
	Finish.apply_finish(bank,Config.POWER_BANK,options)
	var ports: int=Config.value(Config.POWER_BANK,options,"hardware","ports",1)
	for index in ports:
		var x: float=(float(index)-float(ports-1)*.5)*.024
		_box(bank,Vector3(x,size.y*.62,-size.z*.5-.002),Vector3(.016,.007,.004),Color("1e2c35"))
	var lights: Array[MeshInstance3D]=[]
	for index in 4:
		var led:=_box(bank,Vector3((float(index)-1.5)*.010,size.y+.003,-size.z*.27),Vector3(.007,.002,.013),Color("192b35"))
		led.material_override.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		lights.append(led)
	bank.set_meta("battery_lights",lights)
	show_charge(bank,percent)
	return bank

static func show_charge(bank: Node3D, percent: int) -> void:
	if bank.get_meta("charge_percent",-1)==percent:return
	bank.set_meta("charge_percent",percent)
	var lights: Array=bank.get_meta("battery_lights")
	var filled:=ceili(float(percent)/25.0)
	for index in lights.size():
		lights[index].material_override.albedo_color=Color("8af8ce") if index<filled else Color("192b35")

static func _box(parent: Node3D, point: Vector3, size: Vector3, tint: Color) -> MeshInstance3D:
	var node:=MeshInstance3D.new()
	var mesh:=BoxMesh.new()
	mesh.size=size
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=tint
	node.mesh=mesh
	node.material_override=mat
	node.position=point
	parent.add_child(node)
	return node
