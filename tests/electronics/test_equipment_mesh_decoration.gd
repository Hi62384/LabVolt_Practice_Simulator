extends SceneTree

const Config=preload("res://scripts/campus/items/equipment_configuration.gd")
const Dialog=preload("res://scripts/ui/store_bundles_equipment/equipment_configurator.gd")
const Artwork=preload("res://scripts/campus/items/mesh_decoration.gd")
const Document=preload("res://scripts/campus/items/decoration_document.gd")

func _initialize() -> void:
	call_deferred("run")

func _button(point: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT, shift := true) -> InputEventMouseButton:
	var event:=InputEventMouseButton.new()
	event.button_index=button
	event.position=point
	event.pressed=pressed
	event.shift_pressed=shift
	return event

func _pointer(point: Vector2) -> InputEventMouseMotion:
	var event:=InputEventMouseMotion.new()
	event.position=point
	event.shift_pressed=true
	return event

func run() -> void:
	create_timer(65).timeout.connect(func():quit(1))
	var game:=load("res://scenes/Main.tscn").instantiate() as Node
	root.add_child(game)
	await process_frame
	var image:=Image.create_empty(32,24,false,Image.FORMAT_RGBA8)
	image.fill(Color("e727a1"))
	var data:=Document.encode(image)
	var phone_art: Dictionary={}
	for kind in Config.DEFINITIONS:
		var dialog:=Dialog.new()
		game.add_child(dialog)
		dialog.build(game.electronics.profile,func(_message: String):pass,{"kind":kind,"price":50,"name":kind},game.electronics._equipment_preview)
		dialog._show_stage(2 if kind==Config.CALCULATOR else 1)
		dialog.present()
		for idle in 3:await process_frame
		var edit: Control=dialog.decoration_editor
		var surface: Control=dialog.surface_editor
		edit._add("paint","")
		assert(edit.base_panel.is_visible_in_tree())
		assert(edit.layer_scroll.custom_minimum_size.y>=160 and edit.paint_buttons.size()==3)
		if kind==Config.LAPTOP:
			var receivers:=Artwork.surfaces(dialog.rendered_product)
			assert(receivers.values().has(dialog.rendered_product.get_meta("equipment_keyboard")))
			assert(receivers.has("trackpad:0"))
			assert(not receivers.values().has(dialog.rendered_product.get_meta("equipment_screen")))
		var at:=Vector2.INF
		for view in [0,2,1,3,4,5,6]:
			dialog._camera_view(view)
			for row in range(1,12):
				for col in range(1,12):
					var point: Vector2=Vector2(col,row)/12.*Vector2(dialog.preview.size)
					if not surface.pick(point).is_empty():
						at=point
						break
				if at.is_finite():break
			if at.is_finite():break
		assert(at.is_finite(),"No visible paintable geometry for "+kind)
		assert(not surface.input(_button(at,true)),"Select applied brush")
		edit.paint_mode=1
		edit.brush_size.value=4.
		assert(surface.input(_button(at,true,MOUSE_BUTTON_WHEEL_UP)))
		assert(edit.brush_size.value==5. and edit.brush_settings().size==5.)
		edit.paint_mode=2
		assert(surface.input(_button(at,true,MOUSE_BUTTON_WHEEL_DOWN)))
		assert(edit.brush_size.value==4.)
		assert(not surface.input(_button(at,true,MOUSE_BUTTON_WHEEL_UP,false)))
		edit.paint_mode=1
		edit.brush_size.value=14.
		assert(not surface.input(_button(at,true,MOUSE_BUTTON_LEFT,false)),"Pan applied brush")
		var segment: String=surface.pick(at).surface.get_slice(":",0)
		edit.paint_segment="nonmatching_segment"
		assert(not surface.input(_button(at,true)),"Paint applied outside the selected segment")
		edit.paint_segment=segment
		var start:=Time.get_ticks_usec()
		assert(surface.input(_button(at,true)))
		var first:=Time.get_ticks_usec()-start
		start=Time.get_ticks_usec()
		surface.input(_pointer(at+Vector2(2,3)))
		var follow:=Time.get_ticks_usec()-start
		assert(surface.input(_button(at,false)))
		print("Surface brush ",kind," start ",first," us, drag ",follow," us, commit ",Time.get_ticks_usec()-start-follow," us")
		assert(not edit.design[0].get("mesh_paint",{}).is_empty(),"Paint missing on "+kind)
		var painted: Dictionary=edit.design[0].mesh_paint.duplicate()
		var paint_key: String=painted.keys()[0]
		assert(paint_key.get_slice(":",0)==segment and Document.decode(painted[paint_key]).get_width()==Document.PIXELS)
		var copy: Array=JSON.parse_string(JSON.stringify(edit.design))
		assert(Document.clean(copy)!=null)
		copy[0].mesh_paint["../../other:0"]=painted[paint_key]
		assert(Document.clean(copy)==null)
		var receiver: MeshInstance3D=Artwork.surfaces(dialog.rendered_product)[paint_key]
		assert(_overlay(receiver)!=null and _overlay(receiver).mesh==receiver.mesh,"Artwork does not follow receiver")
		edit._undo()
		assert(edit.design[0].get("mesh_paint",{}).is_empty())
		edit._redo()
		assert(edit.design[0].mesh_paint==painted)
		assert(surface.input(_button(at,true,MOUSE_BUTTON_RIGHT)))
		assert(surface.input(_button(at,false,MOUSE_BUTTON_RIGHT)))
		assert(edit.design[0].mesh_paint!=painted,"Right click did not erase "+kind)
		edit._add("image","" if kind==Config.NOTEBOOK else data)
		edit._set_layer("glow",8.,false)
		edit._set_layer("indent",-2.,false)
		if kind==Config.PHONE:
			dialog._camera_view(2)
			at=dialog.camera.unproject_position(dialog.rendered_product.global_position)
		if kind==Config.NOTEBOOK:
			edit._set_layer("data",data,true)
		else:
			assert(surface.input(_button(at,true)))
			assert(surface.input(_button(at,false)))
		assert(edit.design[1].has("projection"),"Image projection missing on "+kind)
		assert(Document.clean(edit.design)!=null)
		if kind==Config.PHONE:
			var coordinates: Array=edit.details.find_children("*","SpinBox",true,false).filter(func(field):return field.suffix=="cm")
			assert(coordinates.size()==2 and coordinates[0].allow_greater and coordinates[1].allow_lesser)
			var anchor: MeshInstance3D=Artwork.surfaces(dialog.rendered_product)[edit.design[1].projection.surface]
			var initial: Transform3D=Artwork.image_frame(anchor,edit.design[1],image.get_size()).transform
			coordinates[0].value=2.5
			coordinates[1].value=-1.25
			var moved: Transform3D=Artwork.image_frame(anchor,edit.design[1],image.get_size()).transform
			assert(moved.origin.is_equal_approx(initial.origin+initial.basis.x*.025-initial.basis.y*.0125))
			var x_input: LineEdit=coordinates[0].get_line_edit()
			x_input.text="100000"
			x_input.text_submitted.emit(x_input.text)
			await process_frame
			assert(Document.clean(edit.design)[1].position_cm==[100000.,-1.25])
			coordinates[0].value=0.
			coordinates[1].value=0.
		receiver=Artwork.surfaces(dialog.rendered_product)[edit.design[1].projection.surface]
		var projected:=_overlay(receiver,true)
		assert(projected!=null and projected.mesh==receiver.mesh,"Missing mesh-conforming image on "+kind)
		assert(projected.material_override.get_shader_parameter("projected"))
		assert(projected.material_override.get_shader_parameter("indent")==-2.)
		edit._set_layer("glow",0.,false)
		assert(projected.material_override.get_shader_parameter("visibility_depth") is Texture2D)
		if kind==Config.PHONE:
			if DisplayServer.get_name()!="headless":
				for tick in 2:await process_frame
				assert(surface.handles.size()==4)
				var corner: Vector2=surface.handles[0]
				var center: Vector2=(corner+surface.handles[2])*.5
				assert(surface.input(_button(corner,true)))
				assert(surface.drag=="resize")
				assert(surface.input(_pointer(center+(corner-center)*1.25)))
				assert(surface.input(_button(corner,false)))
				assert(is_equal_approx(edit.design[1].size,.75))
				await process_frame
				var turn: Vector2=surface.rotate_handle
				center=(surface.handles[0]+surface.handles[2])*.5
				assert(surface.input(_button(turn,true)))
				assert(surface.drag=="rotate")
				assert(surface.input(_pointer(center+(turn-center).rotated(.5))))
				assert(surface.input(_button(turn,false)))
				assert(absf(edit.design[1].angle)>20.)
				for tick in 2:await process_frame
				await RenderingServer.frame_post_draw
				var viewport_pixels:=dialog.preview.get_texture().get_image()
				var displayed:=viewport_pixels.get_pixelv(Vector2i(at))
				assert(displayed.r>displayed.g+.10 and displayed.b>displayed.g+.10,"Projected image did not render on the phone: "+displayed.to_html())
				if OS.get_environment("LABVOLT_CAPTURE_MESH_TEST")=="1":
					root.get_texture().get_image().save_png("res://.godot/mesh-art-preview.png")
			phone_art=dialog.configuration.duplicate(true)
		edit._save()
		edit._reset()
		edit._load()
		assert(edit.design[1].has("projection"))
		dialog.queue_free()
		await process_frame
	var player: RefCounted=game.electronics.profile
	player.data.dollars=10000
	player.buy_smartphone("basic",6,"",phone_art)
	assert(player.operation_succeeded)
	var bought: Dictionary=player.data.dorm.smartphones.values().back()
	assert(Config.same_configuration(Config.PHONE,bought.configuration,phone_art))
	const Handset=preload("res://scripts/campus/phones/phone_handset.gd")
	var world_model:=Node3D.new()
	game.add_child(world_model)
	Handset.build(world_model)
	Handset.apply_appearance(world_model,Config.phone_appearance(bought))
	var mesh: MeshInstance3D=Artwork.surfaces(world_model)[phone_art.decoration[1].projection.surface]
	assert(_overlay(mesh,true)!=null)
	print("EQUIPMENT_MESH_DECORATION PASS")
	quit()

func _overlay(mesh: MeshInstance3D, projected := false) -> MeshInstance3D:
	for child in mesh.get_children():
		if child.has_meta("decoration_overlay") and child.material_override.get_shader_parameter("projected")==projected:return child
	return null
