class_name ComponentShopFitout
extends Node3D
## Physical presentation adapters for the existing shop/trade actions.
## This node does not own inventory, money, authority, saves, or page routing.

const MESH_ROOT := "res://assets/campus/decor/meshes/"
var stations: Dictionary={}

func build() -> Dictionary:
	if not stations.is_empty():return stations.duplicate()
	stations.shop=_station("ComponentCounter",Vector3(22,0,1),"shop","Electronics Store","component_counter",Color("a77b52"),Vector3(2.8,1.05,.9))
	_mesh(stations.shop,"parts_display",Vector3(0,0,1.25),Color("3b716f"),PI)
	_label(stations.shop,"COMPONENTS • KITS • TEST LEADS",Vector3(0,1.68,1.22),PI,Color("d8d0b9"))
	stations.trade=_station("PlayerTradeCounter",Vector3(30,0,1),"trade","Player trading counter","trade_counter",Color("bd964f"),Vector3(2.5,1.05,1.5))
	_mesh(stations.trade,"campus_chair",Vector3(-1.25,0,0),Color("29445c"),-PI/2)
	_mesh(stations.trade,"campus_chair",Vector3(1.25,0,0),Color("29445c"),PI/2)
	_label(stations.trade,"PLAYER TRADING",Vector3(0,1.45,.15),0,Color("d8d0b9"))
	return stations.duplicate()

func activation_contract_valid() -> bool:
	if stations.size()!=2:return false
	for page in ["shop","trade"]:
		var body: Node=stations.get(page)
		if not is_instance_valid(body) or body.get_meta("role","")!="shop_station" or body.get_meta("page","")!=page:return false
	return true

func _station(node_name: String,at: Vector3,page: String,station_label: String,mesh_id: String,color: Color,hit_size: Vector3) -> StaticBody3D:
	var body:=StaticBody3D.new();body.name=node_name;body.position=at;body.collision_layer=4;body.collision_mask=0;body.set_meta("role","shop_station");body.set_meta("page",page);body.set_meta("label",station_label);add_child(body)
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=hit_size;collision.shape=shape;collision.position.y=hit_size.y*.5;body.add_child(collision)
	_mesh(body,mesh_id,Vector3.ZERO,color,0)
	return body

func _mesh(parent: Node3D,mesh_id: String,at: Vector3,color: Color,yaw: float) -> MeshInstance3D:
	var instance:=MeshInstance3D.new();instance.mesh=load(MESH_ROOT+mesh_id+".obj");instance.position=at;instance.rotation.y=yaw
	var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=.7;material.metallic=.08;instance.material_override=material;parent.add_child(instance);return instance

func _label(parent: Node3D,value: String,at: Vector3,yaw: float,color: Color) -> void:
	var label:=Label3D.new();label.text=value;label.position=at;label.rotation.y=yaw;label.font_size=44;label.pixel_size=.0035;label.modulate=color;label.outline_size=8;label.outline_modulate=Color("17252b");parent.add_child(label)
