extends Node3D
## Candidate replacement for component_shop_fitout.gd; preserve shop/trade metadata.
var stations: Dictionary={}
var material_cache: Dictionary={}

func build(include_trade := true) -> Dictionary:
	if not stations.is_empty():return stations.duplicate()
	stations.shop=_station("ComponentCounter",Vector3(22,0,1),"shop","Electronics Store",Vector3(2.98,1.05,.9))
	_box(stations.shop,Vector3(0,.47,0),Vector3(2.76,.94,.70),"465f62")
	_box(stations.shop,Vector3(0,.99,0),Vector3(2.98,.12,.90),"b58b61")
	if include_trade:
		for x in [-1.02,-.34,.34,1.02]:
			_box(stations.shop,Vector3(x,1.08,-.15),Vector3(.49,.13,.36),"7b9b94")
			_round(stations.shop,Vector3(x,1.22,-.15),.12,.12,"c1a471")
		stations.trade=_station("PlayerTradeCounter",Vector3(30,0,1),"trade","Player trading counter",Vector3(2.5,1.05,1.5))
		var table_hit := stations.trade.get_child(0) as CollisionShape3D
		var table_shape := CylinderShape3D.new()
		table_shape.radius=1.12
		table_shape.height=1.05
		table_hit.shape=table_shape
		# Complete unbroken table top; shallow trays lie above, not cut into, its surface.
		_round(stations.trade,Vector3(0,.78,0),1.12,.14,"b6955d")
		_round(stations.trade,Vector3(0,.38,0),.13,.72,"59656b")
		_round(stations.trade,Vector3(0,.05,0),.48,.1,"59656b")
		for x in [-.53,.53]:_box(stations.trade,Vector3(x,.89,0),Vector3(.58,.035,.38),"d3c7a8")
		for x in [-1.52,1.52]:_chair(stations.trade,x)
	return stations.duplicate()

func activation_contract_valid(include_trade := true) -> bool:
	var pages := ["shop","trade"] if include_trade else ["shop"]
	if stations.size()!=pages.size():return false
	for page in pages:
		var body: Node=stations.get(page)
		if not is_instance_valid(body) or body.get_meta("role","")!="shop_station" or body.get_meta("page","")!=page:return false
	return true

func _station(node_name: String,at: Vector3,page: String,label: String,hit_size: Vector3) -> StaticBody3D:
	var body:=StaticBody3D.new();body.name=node_name;body.position=at;body.collision_layer=5;body.collision_mask=0;body.set_meta("role","shop_station");body.set_meta("page",page);body.set_meta("label",label);add_child(body)
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=hit_size;collision.shape=shape;collision.position.y=hit_size.y*.5;body.add_child(collision)
	return body

func _mat(hex: String) -> StandardMaterial3D:
	if material_cache.has(hex):return material_cache[hex]
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color(hex);mat.roughness=.73;material_cache[hex]=mat;return mat

func _box(parent: Node3D,at: Vector3,size: Vector3,hex: String) -> void:
	var mesh:=BoxMesh.new();mesh.size=size;var visual:=MeshInstance3D.new();visual.mesh=mesh;visual.position=at;visual.material_override=_mat(hex);parent.add_child(visual)

func _round(parent: Node3D,at: Vector3,radius: float,height: float,hex: String) -> void:
	var mesh:=CylinderMesh.new();mesh.top_radius=radius;mesh.bottom_radius=radius;mesh.height=height;mesh.radial_segments=24
	var visual:=MeshInstance3D.new();visual.mesh=mesh;visual.position=at;visual.material_override=_mat(hex);parent.add_child(visual)

func _chair(parent: Node3D,x: float) -> void:
	var seat:=StaticBody3D.new();seat.collision_mask=0;seat.position=Vector3(x,0,0);seat.rotation.y=PI/2 if x<0 else -PI/2;parent.add_child(seat)
	var hit := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size=Vector3(.54,.92,.56)
	hit.shape=shape
	hit.position.y=.46
	seat.add_child(hit)
	_box(seat,Vector3(0,.45,0),Vector3(.54,.1,.52),"35505b")
	_box(seat,Vector3(0,.79,.24),Vector3(.54,.62,.08),"35505b")
	for xx in [-.21,.21]:
		for zz in [-.19,.19]:_box(seat,Vector3(xx,.21,zz),Vector3(.045,.42,.045),"59656b")
