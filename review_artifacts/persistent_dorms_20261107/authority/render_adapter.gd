extends RefCounted
const Dorm=preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
const Rules=preload("res://scripts/campus/dorms/customization/placement_rules.gd")
static func mark(node: Node,label: String) -> void:
	var groups := {"BedFrame":"bed","Headboard":"bed","Mattress":"bed","Duvet":"bed","Pillow":"bed","Bedside":"bedside","StudyDesk":"study_desk","DeskLeg":"study_desk","Laptop":"desk_laptop","Notebook":"study_desk","Chair":"study_chair","Wardrobe":"wardrobe","StorageCabinet":"storage_cabinet","Shelf":"shelf","Rug":"rug","Plant":"plant","bedside_lamp":"bedside_lamp","desk_lamp":"desk_lamp"}
	for prefix in groups:
		if label.begins_with(prefix):node.set_meta("furniture",groups[prefix]);return
static func style(saved: Dictionary) -> Dictionary:
	var choices: Dictionary=saved.get("styles",{})
	return {"wall":{"classic":"f2eee5","sage":"b5c0aa","sand":"d6c7af","slate":"8b9ba5"}.get(choices.get("wall","classic"),"f2eee5"),"floor":{"tile":"c6c1b5","warm_tile":"bcae99","wood":"92765a"}.get(choices.get("floor","tile"),"c6c1b5"),"bedding":{"teal":"5b827d","blue":"667e9b","cream":"e5dcc5","rust":"ad7459"}.get(choices.get("bedding","teal"),"5b827d")}
static func apply(room: Node3D,contract: Dictionary,saved: Dictionary) -> void:
	var originals := {}
	for item in Dorm.starter_layout().items:originals[item.id]=item
	var items := {}
	for item in saved.get("items",[]):items[item.id]=item
	var mirror := 1.0 if contract.side=="west" else -1.0
	for node in room.get_children():
		var id := str(node.get_meta("furniture",""))
		if id.is_empty():continue
		if not items.has(id):
			if node is Node3D:node.hide()
			if node is CollisionObject3D:node.collision_layer=0
			continue
		var old: Dictionary=originals[id];var item: Dictionary=items[id]
		var base := Vector3(float(old.x)*mirror,0,float(old.z))
		var target := Vector3(float(item.x)*mirror,0,float(item.z))
		var offset: Vector3=node.position-contract.center-base
		var angle := float(item.rotation)*PI*.5*mirror
		node.position=contract.center+target+offset.rotated(Vector3.UP,angle)
		node.rotation.y+=angle
	for item in items.values():
		var kind: String=item.kind
		if kind=="display":
			var display := MeshInstance3D.new();var mesh := BoxMesh.new();mesh.size=Vector3(.3,.04,.25);display.mesh=mesh
			var material := StandardMaterial3D.new();material.albedo_color=Color("39775b");material.roughness=.9;display.material_override=material
			display.position=contract.center+Vector3(float(item.x)*mirror,1.55 if float(item.z)>4 else .87,float(item.z));room.add_child(display)
		if kind in Rules.ON_SURFACE or kind in Rules.NON_SOLID:continue
		var rect: Rect2=Rules.footprint(item)
		var body := StaticBody3D.new();body.collision_layer=1;body.collision_mask=0
		body.position=contract.center+Vector3(float(item.x)*mirror,.5,float(item.z))
		var collision := CollisionShape3D.new();var shape := BoxShape3D.new();shape.size=Vector3(rect.size.x,1,rect.size.y);collision.shape=shape;body.add_child(collision);room.add_child(body)

