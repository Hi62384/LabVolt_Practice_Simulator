extends RefCounted

const Document=preload("res://scripts/campus/items/decoration_document.gd")
const Geometry=preload("res://scripts/campus/items/EquipmentSurfaceGeometry.cs")
const ShaderResource=preload("res://scripts/campus/items/mesh_decoration.gdshader")
const CACHE_LIMIT:=48
static var texture_cache: Dictionary={}
static var depth_builder: RefCounted

static func surfaces(root: Node3D, include_blockers := false) -> Dictionary:
	var results: Dictionary={}
	var occurrences: Dictionary={}
	var meshes:=root.find_children("*","MeshInstance3D",true,false)
	if root is MeshInstance3D: meshes.push_front(root)
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh==null or mesh.has_meta("decoration_overlay") or not mesh.visible: continue
		var segment: String=mesh.get_meta("material_segment","")
		if segment.is_empty() and mesh.get_parent().name=="DecorationSurface":continue
		var usable: bool=not segment.is_empty() and not mesh.get_meta("paint_protected",false)
		if not usable:
			if include_blockers: results["#"+str(mesh.get_instance_id())]=mesh
			continue
		var order:int=occurrences.get(segment,0)
		occurrences[segment]=order+1
		results["%s:%d"%[segment,order]]=mesh
	return results

static func roots(root: Node3D) -> void:
	for mesh in root.find_children("*","MeshInstance3D",true,false):
		if mesh.has_meta("decoration_overlay"):
			mesh.get_parent().remove_child(mesh)
			mesh.queue_free()

# Overlay geometry uses the original receiver mesh and UVs. Projected images
# are clipped per fragment in three dimensions, including on curved surfaces.
static func apply(root: Node3D, design: Array) -> void:
	var has_mesh_content:=false
	for layer in design:
		has_mesh_content=has_mesh_content or layer.has("projection") or layer.has("mesh_paint")
	if not has_mesh_content and not root.has_meta("mesh_decoration_applied"):return
	roots(root)
	root.set_meta("mesh_decoration_applied",true)
	if not has_mesh_content:return
	var receivers:=surfaces(root)
	var blockers: Array[MeshInstance3D]=[]
	for index in design.size():
		var layer: Dictionary=design[index]
		if not layer.visible or layer.opacity<=0.:continue
		if layer.has("projection") and not layer.data.is_empty():
			var anchor: MeshInstance3D=receivers.get(layer.projection.surface)
			var texture:=_texture(layer.data)
			if anchor==null or texture==null:continue
			var frame:=image_frame(anchor,layer,texture.get_size())
			if frame.is_empty():continue
			var from_world: Transform3D=frame.transform.affine_inverse()
			var target_segment: String=layer.get("target_segment","")
			var half_size:=Vector3(frame.size.x*.5,frame.size.y*.5,frame.thickness)
			var projector_bounds:=AABB(-half_size,half_size*2.)
			var matches: Dictionary={}
			for id in receivers:
				if not target_segment.is_empty() and id.get_slice(":",0)!=target_segment:continue
				var target: MeshInstance3D=receivers[id]
				var relative:=from_world*target.global_transform
				var bounds: AABB=relative*target.get_aabb()
				if bounds.grow(.00005).intersects(projector_bounds):matches[id]=relative
			if matches.is_empty():continue
			if depth_builder==null:depth_builder=Geometry.new()
			if blockers.is_empty():blockers.assign(surfaces(root,true).values())
			var depth: Image=depth_builder.ProjectionDepth(blockers,from_world,frame.size,frame.thickness)
			var visibility:=ImageTexture.create_from_image(depth)
			for id in matches:
				var target: MeshInstance3D=receivers[id]
				var relative: Transform3D=matches[id]
				var material:=_overlay(target,texture,layer,index)
				material.set_shader_parameter("projected",true)
				material.set_shader_parameter("visibility_depth",visibility)
				material.set_shader_parameter("projector_from_mesh",relative)
				material.set_shader_parameter("normal_from_mesh",relative.basis.inverse().transposed())
				material.set_shader_parameter("dimensions",frame.size)
				material.set_shader_parameter("thickness",frame.thickness)
				material.set_shader_parameter("crop",frame.crop)
		elif layer.kind=="paint":
			var images: Dictionary=layer.get("mesh_paint",{})
			for id in images:
				var target: MeshInstance3D=receivers.get(id)
				if target==null:continue
				var texture:=_texture(images[id])
				if texture!=null:_overlay(target,texture,layer,index)

static func preview_paint(root: Node3D, id: String, image: Image, layer: Dictionary, index: int) -> ImageTexture:
	var texture:=ImageTexture.create_from_image(image)
	var target: MeshInstance3D=surfaces(root).get(id)
	if target==null:return texture
	for node in target.get_children():
		if node.has_meta("artwork_layer") and node.get_meta("artwork_layer")==index:
			node.material_override.set_shader_parameter("pattern",texture)
			return texture
	var material:=_overlay(target,texture,layer,index)
	material.set_shader_parameter("projected",false)
	return texture

static func image_frame(anchor: MeshInstance3D, layer: Dictionary, texture_size: Vector2) -> Dictionary:
	var transform:=anchor.global_transform
	var shape:=anchor.get_aabb()
	var projection:Dictionary=layer.projection
	var center:=transform*(shape.get_center()+shape.size*Document.vector(projection.center))
	var normal:=(transform.basis.inverse().transposed()*Document.vector(projection.normal)).normalized()
	var right:=(transform.basis*Document.vector(projection.right)).slide(normal).normalized()
	var up:=normal.cross(right)
	var span:=projection_span(anchor,layer)
	var coordinates:=image_position(layer,span)
	center+=right*(float(coordinates[0])*.01)+up*(float(coordinates[1])*.01)
	if not center.is_finite():return {}
	var angle:=deg_to_rad(float(layer.angle))
	right=right.rotated(normal,angle)
	up=up.rotated(normal,angle)
	var crop:=Vector4(layer.crop_left,layer.crop_top,1.-layer.crop_left-layer.crop_right,1.-layer.crop_top-layer.crop_bottom)
	var aspect:=maxf(.025,texture_size.x*crop.z/maxf(1.,texture_size.y*crop.w))
	var footprint:=Vector2(aspect,1.)/maxf(1.,aspect)*span*float(layer.size)*Vector2(layer.width,layer.height)
	var thickness:=maxf(.00035,minf(span*.10,minf(footprint.x,footprint.y)*.34))
	return {"transform":Transform3D(Basis(right,up,normal),center),"size":footprint,"thickness":thickness,"crop":crop}

static func projection_span(anchor: MeshInstance3D,layer: Dictionary) -> float:
	if layer.has("reference_span"):return float(layer.reference_span)
	var world_size:=anchor.get_aabb().size*anchor.global_basis.get_scale().abs()
	return maxf(world_size.x,maxf(world_size.y,world_size.z))

static func image_position(layer: Dictionary,span: float) -> Array:
	if layer.has("position_cm"):return layer.position_cm.duplicate()
	var offset:=Vector2(float(layer.x)-.5,.5-float(layer.y))*span*100.
	offset=offset.rotated(deg_to_rad(float(layer.angle)))
	return [offset.x,offset.y]

static func _overlay(target: MeshInstance3D, texture: Texture2D, layer: Dictionary, index: int) -> ShaderMaterial:
	var overlay:=MeshInstance3D.new()
	overlay.set_meta("decoration_overlay",true)
	overlay.set_meta("artwork_layer",index)
	overlay.mesh=target.mesh
	overlay.layers=target.layers
	overlay.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material:=ShaderMaterial.new()
	material.shader=ShaderResource
	material.render_priority=index
	var tint:=Color(layer.color)
	tint.a=layer.opacity
	material.set_shader_parameter("tint",tint)
	material.set_shader_parameter("glow_color",Color(layer.glow_color))
	material.set_shader_parameter("glow",layer.glow)
	material.set_shader_parameter("roughness",layer.roughness)
	material.set_shader_parameter("metallic",layer.metallic)
	material.set_shader_parameter("indent",layer.get("indent",0.0))
	material.set_shader_parameter("pattern",texture)
	material.set_shader_parameter("projected",false)
	material.set_shader_parameter("separation",.00004*float(index+1))
	overlay.material_override=material
	target.add_child(overlay)
	return material

static func _texture(data: String) -> Texture2D:
	var key:=data.sha256_text()
	if texture_cache.has(key):return texture_cache[key]
	var decoded:=Document.decode(data)
	if decoded==null:return null
	if texture_cache.size()>=CACHE_LIMIT:texture_cache.erase(texture_cache.keys()[0])
	var texture:=ImageTexture.create_from_image(decoded)
	texture_cache[key]=texture
	return texture
