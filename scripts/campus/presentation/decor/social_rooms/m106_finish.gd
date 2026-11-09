extends Node3D
## M106 visual finish, local to registry center (26,0,33).
var mats: Dictionary = {}
func mat(color: String) -> StandardMaterial3D:
	if mats.has(color): return mats[color]
	var m := StandardMaterial3D.new(); m.albedo_color=Color(color);m.roughness=.85
	if color == "fff2dc":
		m.emission_enabled = true
		m.emission = m.albedo_color
		m.emission_energy_multiplier = .45
	mats[color]=m;return m
func panel(at: Vector3,size: Vector3,color: String) -> void:
	var box := BoxMesh.new();box.size=size
	var item := MeshInstance3D.new();item.mesh=box;item.position=at
	item.material_override=mat(color);item.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(item)
func batch(points: Array,size: Vector3,color: String) -> void:
	var box := BoxMesh.new();box.size=size
	var mm := MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=box;mm.instance_count=points.size()
	for i in points.size():mm.set_instance_transform(i,Transform3D(Basis.IDENTITY,points[i]))
	var item := MultiMeshInstance3D.new();item.multimesh=mm;item.material_override=mat(color)
	item.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(item)
func text(value: String,at: Vector3,color: String,size: float=.003) -> void:
	var item := Label3D.new();item.text=value;item.position=at;item.font_size=40
	item.pixel_size=size;item.modulate=Color(color);item.no_depth_test=false
	item.billboard=BaseMaterial3D.BILLBOARD_DISABLED;add_child(item)
func build(_menu: Dictionary) -> bool:
	var floor_a: Array=[];var floor_b: Array=[]
	for x in range(20):
		for z in range(12):(floor_a if (x+z)%4==0 else floor_b).append(Vector3(-9.5+x,.008,-5.5+z))
	batch(floor_a,Vector3(.984,.012,.984),"6c7b7e")
	batch(floor_b,Vector3(.984,.012,.984),"738287")
	# West entry x=-10,z=0 remains fully open. Existing right wall window
	# insets at x~9.78,z +/-3.4 remain in front of this backing finish.
	for z in [-5.88,5.88]:
		panel(Vector3(0,1,z),Vector3(19.8,1.9,.035),"506b75")
		panel(Vector3(0,2.95,z),Vector3(19.8,1.99,.035),"dedfd8")
		panel(Vector3(0,.11,z),Vector3(19.8,.20,.07),"334e59")
	for z in [-3.65,3.65]:
		panel(Vector3(-9.88,1,z),Vector3(.035,1.9,4.55),"506b75")
		panel(Vector3(-9.88,2.95,z),Vector3(.035,1.99,4.55),"dedfd8")
	panel(Vector3(9.88,1,0),Vector3(.035,1.9,11.8),"506b75")
	panel(Vector3(9.88,2.95,0),Vector3(.035,1.99,11.8),"dedfd8")
	var ceiling_a: Array=[];var ceiling_b: Array=[]
	for x in range(10):
		for z in range(6):(ceiling_a if (x+z)%3 else ceiling_b).append(Vector3(-9+x*2,3.96,-5+z*2))
	batch(ceiling_a,Vector3(1.975,.025,1.975),"e4e7df")
	batch(ceiling_b,Vector3(1.975,.025,1.975),"d7dfda")
	var lights: Array=[]
	for x in [-5,0,5]:
		for z in [-3,3]:lights.append(Vector3(x,3.925,z))
	batch(lights,Vector3(1.22,.038,1.22),"505c62")
	for index in lights.size():lights[index] -= Vector3(0,.027,0)
	batch(lights,Vector3(1.08,.018,1.08),"fff2dc")
	# Counter lies local z=-2.5. Existing 6.2m top and collider remain.
	panel(Vector3(0,3.71,-4.37),Vector3(6.65,.22,2.79),"9e333b")
	panel(Vector3(0,3.583,-4.37),Vector3(6.54,.04,2.67),"ba9a7c")
	for x in [-2.45,-.8,.8,2.45]:
		panel(Vector3(x,3.552,-3.31),Vector3(.24,.025,.24),"fff2dc")
	# Signage is backed and physically fixed on the rear wall.
	panel(Vector3(0,3.20,-5.79),Vector3(4.0,.52,.06),"9e333b")
	text("Tim Hortons",Vector3(0,3.20,-5.745),"f4eee5",.0048)
	# The mounted social profile already supplies a 6.2 x 1m thick top,
	# red ribbed front, coffee machine, pastry tray, four tables and red chairs.
	# The pastry tray spans x=-2.4..-.6 at y1.18..1.68. Add a framed
	# clear guard supported by its perimeter, without replacing pastry items.
	var glass := StandardMaterial3D.new()
	glass.albedo_color=Color("b8d5d6",.26)
	glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness=.28
	glass.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	for x in [-2.39,-.61]:
		panel(Vector3(x,1.45,-2.5),Vector3(.025,.54,.52),"343e44")
	panel(Vector3(-1.5,1.71,-2.5),Vector3(1.82,.025,.55),"343e44")
	var shield := BoxMesh.new();shield.size=Vector3(1.76,.46,.018)
	var shield_node := MeshInstance3D.new();shield_node.mesh=shield
	shield_node.position=Vector3(-1.5,1.45,-2.215)
	shield_node.material_override=glass;shield_node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shield_node)
	# Small payment terminal on the real counter surface, at the original
	# customer service end; transactional authority remains FacilityHost.
	panel(Vector3(2.45,1.25,-2.45),Vector3(.47,.13,.35),"343e44")
	panel(Vector3(2.45,1.34,-2.51),Vector3(.38,.04,.22),"a9b6af")
	# Supported rear coffee shelf and equipment silhouette; no false register.
	panel(Vector3(4.2,1.14,-5.45),Vector3(2.2,.09,.42),"674738")
	for x in [3.35,5.05]:panel(Vector3(x,.63,-5.45),Vector3(.09,1.17,.36),"343e44")
	panel(Vector3(4.2,1.47,-5.45),Vector3(.66,.64,.34),"343e44")
	for x in [3.25,3.55]:panel(Vector3(x,1.28,-5.42),Vector3(.16,.25,.16),"ede5d6")
	# Existing social profile supplies red chairs, tables, pastry display,
	# countertop coffee machine, tray stack, recycling and plants.
	return true
