extends RefCounted

const Document = preload("res://scripts/campus/items/decoration_document.gd")
const MeshArtwork = preload("res://scripts/campus/items/mesh_decoration.gd")
const CACHE_LIMIT := 32
static var textures := {}

static func attach(parent: Node3D, design: Array, center: Vector3, rotation: Vector3, area: Vector2, layers:=1, model: Node3D=null) -> void:
	var previous:=parent.get_node_or_null("DecorationSurface")
	if is_instance_valid(previous):
		if previous.get_meta("design",[])==design:return
		parent.remove_child(previous)
		previous.queue_free()
	MeshArtwork.apply(parent if model==null else model,design)
	if design.is_empty():return
	var surface:=Node3D.new()
	surface.name="DecorationSurface"
	surface.position=center
	surface.rotation=rotation
	surface.set_meta("design",design.duplicate(true))
	parent.add_child(surface)
	for index in design.size():
		var layer: Dictionary=design[index]
		if not layer.visible or layer.opacity<=0.0 or layer.data.is_empty() or layer.has("projection"):continue
		_add(surface,layer,index,area,layers)

static func _add(surface: Node3D, layer: Dictionary, index: int, area: Vector2, layers: int) -> void:
	var target_aspect:=1.0
	var texture: Texture2D
	var crop := Rect2(Vector2(layer.crop_left,layer.crop_top),Vector2(1.0-layer.crop_left-layer.crop_right,1.0-layer.crop_top-layer.crop_bottom))
	var text_node: Label3D
	if layer.kind in ["paint","image"]:
		texture=_texture(layer.data)
		if texture==null:return
		target_aspect=float(texture.get_width())*crop.size.x/(float(texture.get_height())*crop.size.y) if layer.kind=="image" else area.x/area.y
	elif layer.kind=="text":
		text_node=Label3D.new()
		text_node.text=layer.data
		text_node.font=ThemeDB.fallback_font
		text_node.font_size=32
		text_node.outline_size=0
		var measure:=text_node.font.get_string_size(layer.data,HORIZONTAL_ALIGNMENT_LEFT,-1,32)
		target_aspect=measure.x/maxf(1.0,measure.y)
		text_node.set_meta("line_height",measure.y)
	elif layer.kind=="shape":
		target_aspect=4.0 if layer.data=="Trim" else 2.0 if layer.data=="Panel" else 1.0
	var width:=target_aspect*float(layer.get("width",1.0))
	var height:=float(layer.get("height",1.0))
	var angle:=deg_to_rad(float(layer.angle))
	var available:=Vector2(absf(cos(angle))*width+absf(sin(angle))*height,absf(sin(angle))*width+absf(cos(angle))*height)
	var neutral:=Vector2(absf(cos(angle))*target_aspect+absf(sin(angle)),absf(sin(angle))*target_aspect+absf(cos(angle)))
	var scale:=minf(minf(area.x/available.x,area.y/available.y),minf(area.x/neutral.x,area.y/neutral.y)*float(layer.size))
	var footprint:=available*scale
	var position:=Vector3((float(layer.x)-.5)*(area.x-footprint.x),(.5-float(layer.y))*(area.y-footprint.y),.00012*(index+1))
	var box:=Vector2(width,height)*scale
	var tint:=Color(layer.color)
	tint.a=layer.opacity
	if text_node!=null:
		text_node.position=position
		text_node.rotation.z=angle
		text_node.pixel_size=box.y/float(text_node.get_meta("line_height"))
		text_node.modulate=tint
		text_node.render_priority=index
		text_node.layers=layers
		text_node.shaded=float(layer.glow)<=0.0
		surface.add_child(text_node)
		return
	var decal:=MeshInstance3D.new()
	decal.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	decal.layers=layers
	decal.position=position
	decal.rotation.z=angle
	decal.mesh=_shape(layer.data,box) if layer.kind=="shape" else _quad(box)
	if layer.kind=="shape":decal.position.z+=minf(area.x,area.y)*.012
	if layer.kind=="shape" and layer.data in ["Button","Stud"]:decal.rotate_object_local(Vector3.RIGHT,PI/2.0)
	var material:=StandardMaterial3D.new()
	material.albedo_color=tint
	material.albedo_texture=texture
	if layer.kind=="image":
		material.uv1_offset=Vector3(crop.position.x,crop.position.y,0)
		material.uv1_scale=Vector3(crop.size.x,crop.size.y,1)
	material.roughness=layer.roughness
	material.metallic=layer.metallic
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode=[BaseMaterial3D.BLEND_MODE_MIX,BaseMaterial3D.BLEND_MODE_ADD,BaseMaterial3D.BLEND_MODE_MUL][layer.blend]
	material.render_priority=index
	if float(layer.glow)>0.0:
		material.emission_enabled=true
		material.emission=Color(layer.glow_color)
		material.emission_energy_multiplier=layer.glow
		material.emission_texture=texture
	decal.material_override=material
	surface.add_child(decal)

static func _quad(size: Vector2) -> QuadMesh:
	var mesh:=QuadMesh.new()
	mesh.size=size
	return mesh

static func _shape(kind: String, size: Vector2) -> Mesh:
	var thickness:=size.y*.08
	match kind:
		"Button":
			var mesh:=CylinderMesh.new()
			mesh.radial_segments=20
			mesh.rings=1
			mesh.height=thickness
			mesh.top_radius=size.y*.5
			mesh.bottom_radius=mesh.top_radius
			return mesh
		"Stud":
			var mesh:=SphereMesh.new()
			mesh.radial_segments=16
			mesh.rings=8
			mesh.radius=size.y*.5
			mesh.height=thickness
			mesh.is_hemisphere=true
			return mesh
		_:
			var mesh:=BoxMesh.new()
			mesh.size=Vector3(size.x,size.y,thickness)
			return mesh

static func _texture(data: String) -> Texture2D:
	var key:=data.sha256_text()
	if textures.has(key):return textures[key]
	var image:=Document.decode(data)
	if image==null:return null
	if textures.size()>=CACHE_LIMIT:textures.erase(textures.keys()[0])
	var texture:=ImageTexture.create_from_image(image)
	textures[key]=texture
	return texture
