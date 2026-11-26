extends Control

const Geometry=preload("res://scripts/campus/items/EquipmentSurfaceGeometry.cs")
const Document=preload("res://scripts/campus/items/decoration_document.gd")
const Artwork=preload("res://scripts/campus/items/mesh_decoration.gd")
const INK:=Color("a7ffee")
const DARK:=Color("112c37")
const MAX_SPOTS:=12

var geometry=Geometry.new()
var camera: Camera3D
var editor: Control
var product: Node3D
var surfaces: Dictionary={}
var ids: Array=[]
var hover:=Vector2.INF
var drag:=""
var drag_button:=MOUSE_BUTTON_LEFT
var force_erase:=false
var resize_origin:=Vector2.ZERO
var resize_axis:=Vector2.ZERO
var edge_handles:=PackedVector2Array()
var last_point:=Vector2.ZERO
var raw_pixels: Dictionary={}
var paint_textures: Dictionary={}
var pending: Dictionary={}
var original: Dictionary={}
var handles:=PackedVector2Array()
var rotate_handle:=Vector2.INF
var render_preview: Callable

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE

func refresh_geometry(root: Node3D) -> void:
	if not is_instance_valid(root):return
	var current:=Artwork.surfaces(root,true)
	if product==root and current==surfaces:return
	product=root
	surfaces=current
	ids=surfaces.keys()
	geometry.Clear()
	for index in ids.size():geometry.Register(index,surfaces[ids[index]])

func selection_changed() -> void:
	queue_redraw()

func layer() -> Dictionary:
	return editor.design[editor.active] if is_instance_valid(editor) and editor.visible and editor.active>=0 and editor.active<editor.design.size() else {}

func accepts_brush() -> bool:
	var current:=layer()
	return current.get("kind","")=="paint" and not current.locked and current.visible and editor.paint_mode!=0

func input(event: InputEvent) -> bool:
	var current:=layer()
	if current.is_empty() or current.locked or not current.visible or current.kind not in ["paint","image"]:return false
	if event is InputEventMouseButton and event.button_index==drag_button and not event.pressed and not drag.is_empty():
		finish()
		return true
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):return false
	if not event.shift_pressed:
		hover=Vector2.INF
		if not drag.is_empty():
			finish()
			return true
		queue_redraw()
		return false
	if event is InputEventMouseMotion:
		hover=event.position
		queue_redraw()
		if drag=="brush":
			paint_to(event.position)
		elif not drag.is_empty():
			move_image(event.position)
		return not drag.is_empty()
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT] and event.pressed:
		refresh_geometry(product)
		last_point=event.position
		original=current.duplicate(true)
		drag_button=event.button_index
		if current.kind=="paint":
			if not accepts_brush() or _paint_hit(event.position,editor.paint_segment).is_empty():return false
			force_erase=event.button_index==MOUSE_BUTTON_RIGHT
			raw_pixels.clear()
			paint_textures.clear()
			drag="brush"
			paint_to(event.position)
		elif event.button_index==MOUSE_BUTTON_LEFT and not str(current.data).is_empty():
			var edge:=_handle_index(edge_handles,event.position)
			var corner:=_handle_index(handles,event.position)
			if rotate_handle.distance_to(event.position)<13.:
				drag="rotate"
			elif corner>=0:
				drag="resize"
			elif edge>=0:
				drag="height" if edge%2==0 else "width"
				resize_axis=(edge_handles[edge]-edge_handles[(edge+2)%4]).normalized()
			if drag in ["rotate","resize","height","width"]:
				resize_origin=(handles[0]+handles[2])*.5
			elif not pick(event.position).is_empty() or (handles.size()==4 and Geometry2D.is_point_in_polygon(event.position,handles)):
				drag="move"
				move_image(event.position)
			else:return false
		else:return false
		return true
	return false

func pick(position: Vector2) -> Dictionary:
	var result: Dictionary=geometry.Pick(camera.project_ray_origin(position),camera.project_ray_normal(position))
	if result.is_empty():return result
	var id: String=ids[result.id]
	if id.begins_with("#"):return {}
	result.surface=id
	return result

func _paint_hit(position: Vector2,segment: String) -> Dictionary:
	var hit:=pick(position)
	if hit.is_empty() or (not segment.is_empty() and hit.surface.get_slice(":",0)!=segment):return {}
	return hit

func paint_to(point: Vector2) -> void:
	var brush: Dictionary=editor.brush_settings()
	brush.erase=brush.erase or force_erase
	var flow: float=brush.ink.a
	if flow<=0.:return
	var viewport_height:=maxf(1.,size.y)
	var focal:=viewport_height*.5/tan(deg_to_rad(camera.fov*.5))
	var steps:=clampi(ceili(last_point.distance_to(point)/maxf(1.,float(brush.size)*float(brush.spacing))),1,MAX_SPOTS)
	var saved: Dictionary=original.get("mesh_paint",{})
	var changed: Dictionary={}
	var points:=PackedVector3Array()
	var normals:=PackedVector3Array()
	var radii:=PackedFloat32Array()
	var prior:=last_point
	last_point=point
	for step in range(1,steps+1):
		var hit:=_paint_hit(prior.lerp(point,float(step)/steps),brush.segment)
		if hit.is_empty():continue
		var meters: float=-camera.to_local(hit.point).z
		var radius:=meters*float(brush.size)*1.35/focal
		points.append(hit.point)
		normals.append(hit.normal)
		radii.append(radius)
	if points.is_empty():return
	for index in ids.size():
		var id: String=ids[index]
		if id.begins_with("#") or (not str(brush.segment).is_empty() and id.get_slice(":",0)!=brush.segment):continue
		if not raw_pixels.has(id):
			if brush.erase and not saved.has(id):continue
			var image:=Document.decode(saved[id]) if saved.has(id) else null
			if image!=null:
				image.convert(Image.FORMAT_RGBA8)
				image.resize(Document.PIXELS,Document.PIXELS,Image.INTERPOLATE_BILINEAR)
			raw_pixels[id]=image.get_data() if image!=null else PackedByteArray()
		var pixels: PackedByteArray=geometry.PaintStroke(index,raw_pixels[id],points,normals,radii,brush.ink,brush.hardness,brush.erase)
		if not pixels.is_empty():
			raw_pixels[id]=pixels
			changed[id]=true
	if changed.is_empty():return
	for id in changed:
		var updated:=Image.create_from_data(Document.PIXELS,Document.PIXELS,false,Image.FORMAT_RGBA8,raw_pixels[id])
		if paint_textures.has(id):paint_textures[id].update(updated)
		else:paint_textures[id]=Artwork.preview_paint(product,id,updated,original,editor.active)
	render_preview.call()

func move_image(point: Vector2) -> void:
	pending=original.duplicate(true) if pending.is_empty() else pending
	if drag=="move":
		var hit:=pick(point)
		if hit.is_empty():
			_move_on_image_plane(point)
		else:
			_place_image(hit)
	elif handles.size()==4:
		var base:=last_point-resize_origin
		var delta:=point-resize_origin
		if drag=="rotate":
			pending.angle=wrapf(float(original.angle)-rad_to_deg(base.angle_to(delta)),-180.,180.)
		elif drag=="resize" and base.length()>2.:
			pending.size=clampf(float(original.size)*delta.length()/base.length(),.1,1.)
		elif drag in ["height","width"] and absf(base.dot(resize_axis))>2.:
			pending[drag]=clampf(float(original[drag])*delta.dot(resize_axis)/base.dot(resize_axis),.25,4.)
	var next: Array=editor.design.duplicate(true)
	next[editor.active]=pending
	Artwork.apply(product,next)
	render_preview.call()
	queue_redraw()

func _place_image(hit: Dictionary) -> void:
	var target: MeshInstance3D=surfaces[hit.surface]
	var shape:=target.get_aabb()
	var normal: Vector3=hit.local_normal
	var tangential: Vector3=target.global_basis.inverse()*camera.global_basis.x
	var right:=tangential.slide(normal).normalized()
	if right.is_zero_approx():return
	if not pending.has("reference_span"):
		var previous: MeshInstance3D=surfaces.get(pending.get("projection",{}).get("surface",""),target)
		var extent:=previous.get_aabb().size*previous.global_basis.get_scale().abs()
		pending.reference_span=maxf(extent.x,maxf(extent.y,extent.z))
	var center: Vector3=(hit.local-shape.get_center())/shape.size.max(Vector3.ONE*.00001)
	pending.projection={"surface":hit.surface,"center":Document.array(center),"normal":Document.array(normal),"right":Document.array(right)}
	pending.x=.5
	pending.y=.5

func _move_on_image_plane(point: Vector2) -> void:
	if not pending.has("projection"):return
	var target: MeshInstance3D=surfaces.get(pending.projection.surface)
	var texture:=Artwork._texture(pending.data)
	if not is_instance_valid(target) or texture==null:return
	var frame: Transform3D=Artwork.image_frame(target,pending,texture.get_size()).transform
	var plane:=Plane(frame.basis.z,frame.origin)
	var hit: Variant=plane.intersects_ray(camera.project_ray_origin(point),camera.project_ray_normal(point))
	if hit==null:return
	var shape:=target.get_aabb()
	var center: Vector3=(target.to_local(hit)-shape.get_center())/shape.size.max(Vector3.ONE*.00001)
	if not center.is_finite():return
	if maxf(absf(center.x),maxf(absf(center.y),absf(center.z)))>64.:return
	pending.projection.center=Document.array(center)
	pending.x=.5
	pending.y=.5

func finish() -> void:
	var committed:=true
	if drag=="brush":
		var images: Dictionary=original.get("mesh_paint",{}).duplicate()
		for id in paint_textures:
			var image:=Image.create_from_data(Document.PIXELS,Document.PIXELS,false,Image.FORMAT_RGBA8,raw_pixels[id])
			if image.is_invisible():images.erase(id)
			else:images[id]=Document.encode(image)
		if not paint_textures.is_empty():
			var changed:=original.duplicate(true)
			changed.mesh_paint=images
			committed=editor.replace_active(changed,false)
	elif not pending.is_empty():
		committed=editor.replace_active(pending)
	drag=""
	pending={}
	raw_pixels.clear()
	paint_textures.clear()
	if not committed and is_instance_valid(product):
		Artwork.apply(product,editor.design)
		render_preview.call()
	queue_redraw()

func _handle_index(points: PackedVector2Array, point: Vector2) -> int:
	for index in points.size():
		if points[index].distance_to(point)<10.:return index
	return -1

func _draw() -> void:
	handles.clear()
	edge_handles.clear()
	rotate_handle=Vector2.INF
	var current:=pending if not pending.is_empty() else layer()
	if current.is_empty() or not current.get("visible",false):return
	if current.kind=="paint" and hover.is_finite() and accepts_brush() and not _paint_hit(hover,editor.paint_segment).is_empty():
		var brush: Dictionary=editor.brush_settings()
		var radius:=float(brush.size)*1.35
		draw_arc(hover,radius,0.,TAU,32,DARK,3.,true)
		draw_arc(hover,radius,0.,TAU,32,INK,1.,true)
	if current.kind!="image" or not current.has("projection"):return
	var target: MeshInstance3D=surfaces.get(current.projection.surface)
	var texture:=Artwork._texture(current.data)
	if not is_instance_valid(target) or texture==null:return
	var frame:=Artwork.image_frame(target,current,texture.get_size())
	var origin: Transform3D=frame.transform
	if camera.is_position_behind(origin.origin):return
	var half: Vector2=frame.size*.5
	for point in [Vector2(-half.x,half.y),half,Vector2(half.x,-half.y),-half]:
		handles.append(camera.unproject_position(origin*Vector3(point.x,point.y,0.)))
	var outline:=handles.duplicate()
	outline.append(handles[0])
	draw_polyline(outline,INK,1.5,true)
	if current.locked:return
	var top: Vector2=(handles[0]+handles[1])*.5
	var outward: Vector2=(top-(handles[2]+handles[3])*.5).normalized()
	rotate_handle=top+outward*20.
	draw_line(top,rotate_handle,INK,1.5,true)
	draw_circle(rotate_handle,5.,INK,true,-1.,true)
	for index in handles.size():
		var point:=handles[index]
		draw_rect(Rect2(point-Vector2(4,4),Vector2(8,8)),INK)
		if not current.lock_aspect:
			var edge: Vector2=(point+handles[(index+1)%4])*.5
			edge_handles.append(edge)
			draw_circle(edge,3.5,INK,true,-1.,true)
