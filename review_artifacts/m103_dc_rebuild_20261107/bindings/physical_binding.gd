extends Node3D
## Assembled M103 presentation adapter. Production authority remains dc_lab.request.
const DeviceBinding = preload("res://review_artifacts/m103_dc_rebuild_20261107/bindings/device_binding.gd")
const ScopeSettings = preload("res://scripts/dc_scope/settings.gd")
var binding := DeviceBinding.new()
var physical: Node3D
var labels := {}
var trace: Control
var viewport: SubViewport
var state_buttons := {}
var last_state := {}
var scope_metrics: Label
var hovered: MeshInstance3D

func bind(lab: Node,index: int,model: Node3D) -> void:
	physical=model;binding.configure(lab,index)
	for id in physical.port_targets:
		var panel_target: StaticBody3D=physical.port_targets[id]
		var opening := Marker3D.new();opening.name="ElectricalOpening"
		panel_target.add_child(opening)
		opening.position=panel_target.to_local(physical.socket_surface_position(id))
		var pick := StaticBody3D.new();opening.add_child(pick)
		var hit := CollisionShape3D.new();var shape := SphereShape3D.new();shape.radius=.028
		hit.shape=shape;pick.add_child(hit)
		for child in panel_target.get_children():
			if child is CollisionShape3D:child.disabled=true
		binding.sockets.register_socket(id,opening,pick)
		var halo := MeshInstance3D.new();halo.name="HoverHalo"
		var ring := TorusMesh.new();ring.inner_radius=.028;ring.outer_radius=.034;ring.rings=12;ring.ring_segments=6
		halo.mesh=ring;halo.rotation.x=PI/2;halo.visible=false;opening.add_child(halo)
		var material := StandardMaterial3D.new();material.albedo_color=Color("f7e39c");material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		halo.material_override=material;pick.set_meta("dc_hover_visual",halo)
	for i in 3:
		var prefix := "psu_ch%d_"%(i+1)
		_control(prefix+"voltage",{"op":"channel","index":i,"key":"voltage"},["channels",i,"voltage"],0,30)
		_control(prefix+"limit",{"op":"channel","index":i,"key":"limit"},["channels",i,"limit"],.001,1)
		_control(prefix+"enable",{"op":"channel","index":i,"key":"enabled"})
		state_buttons[prefix+"enable"]=["channels",i,"enabled"]
		_screen("psu_ch%d"%(i+1))
	_control("psu_master",{"op":"master"});state_buttons.psu_master=["master"]
	_control("meter_mode",{"op":"meter_mode_next"})
	_control("meter_range",{"op":"meter_range_next"})
	_control("meter_fuse",{"op":"fuse"})
	for key in ["frequency","amplitude","offset"]:
		var bounds: Array=preload("res://review_artifacts/m103_dc_rebuild_20261107/bindings/control_adapter.gd").GEN[key]
		_control("generator_"+key,{"op":"generator","key":key},["generator",key],float(bounds[0]),float(bounds[1]))
	_control("generator_wave",{"op":"generator","key":"wave"})
	_control("generator_output",{"op":"generator","key":"enabled"});state_buttons.generator_output=["generator","enabled"]
	for i in 2:_control("scope_ch%d_scale"%(i+1),{"op":"scope","channel":i,"key":"scale"},["scope","channels",i,"scale"],.001,1000)
	_control("scope_timebase",{"op":"scope","key":"timebase"},["scope","timebase"],.0001,2)
	_control("scope_trigger",{"op":"scope","key":"trigger"},["scope","trigger"],-10000,10000)
	_control("scope_run",{"op":"scope","key":"running"});state_buttons.scope_run=["scope","running"]
	for i in 4:
		var id := "is%d_enable"%(i+1)
		_control(id,{"op":"current_source","index":i,"key":"enabled"});state_buttons[id]=["current_sources",i,"enabled"]
	_screen("meter");_screen("generator");_scope_screen()
	assert(binding.sockets.openings.size()==34)

func _control(id: String,spec: Dictionary,path: Array=[],minimum := 0.0,maximum := 1.0) -> void:
	assert(physical.control_mounts.has(id))
	var target: StaticBody3D=physical.control_mounts[id]
	binding.bind_control(target,spec)
	if not path.is_empty():binding.bind_knob(target.get_node("ControlGeometry"),path,minimum,maximum)

func _screen(id: String) -> void:
	var mount: Node3D=physical.display_mounts[id]
	var label := Label3D.new();label.name="LiveReading";label.font_size=48
	label.pixel_size=float(mount.get_meta("width"))/1000.0
	label.modulate=Color("b2f1d7");label.no_depth_test=false
	mount.add_child(label);labels[id]=label

func _scope_screen() -> void:
	var mount: Node3D=physical.display_mounts.scope_trace
	viewport=SubViewport.new();viewport.size=Vector2i(840,440);viewport.transparent_bg=false
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED;add_child(viewport)
	trace=preload("res://scripts/scope_trace.gd").new();viewport.add_child(trace)
	trace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	trace.offset_bottom=-64
	scope_metrics=Label.new();scope_metrics.position=Vector2(8,378);scope_metrics.size=Vector2(824,60)
	scope_metrics.add_theme_font_size_override("font_size",14);viewport.add_child(scope_metrics)
	var face := MeshInstance3D.new();var quad := QuadMesh.new()
	quad.size=Vector2(float(mount.get_meta("width")),float(mount.get_meta("height")));face.mesh=quad
	var material := StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture=viewport.get_texture();face.material_override=material;mount.add_child(face)

func action_for(target: Node,right: bool,state: Dictionary) -> Dictionary:
	return binding.action_for(target,right,state)

func port_positions() -> Dictionary:
	return binding.port_positions()

func observe(state: Dictionary,delta: float,relevant: bool) -> void:
	if not relevant and is_instance_valid(hovered):hovered.hide()
	var previous_elapsed := binding.elapsed
	binding.observe(state,delta,relevant)
	if not relevant or previous_elapsed+maxf(delta,0)<.1:return
	_update_hover()
	var result: Dictionary=state.get("result",{})
	for i in 3:
		var id := "s%d"%i
		var voltage := float(result.get("drop",{}).get(id,0));var current := -float(result.get("i",{}).get(id,0))
		labels["psu_ch%d"%(i+1)].text="%s\n%.2f V  %.3f A"%[str(result.get("mode",{}).get(id,"OFF")),voltage,current]
	labels.meter.text="%s\n%s"%[str(state.get("meter_mode","DC V")),str(state.get("meter","—"))]
	var generator: Dictionary=state.generator
	labels.generator.text="%s · %s\n%.1f Hz  %.2f Vpk\nOffset %.2f V"%[generator.wave,"ON" if generator.enabled else "OFF",generator.frequency,generator.amplitude,generator.offset]
	for id in state_buttons:
		var value: Variant=state
		for key in state_buttons[id]:value=value[key]
		var geometry: Node3D=physical.control_mounts[id].get_node("ControlGeometry")
		geometry.position.z=-.008 if bool(value) else 0.0
	physical.control_mounts.meter_mode.get_node("ControlGeometry").rotation.z=TAU*float(preload("res://review_artifacts/m103_dc_rebuild_20261107/bindings/control_adapter.gd").MODES.find(str(state.meter_mode)))/10.0
	var scope_state := {"samples":state.get("samples",[]),"scope":state.get("scope",{}),"acquisition":state.get("scope_acquisition",{})}
	if scope_state!=last_state:
		trace.samples=scope_state.samples;trace.settings=ScopeSettings.normalize(scope_state.scope)
		trace.acquisition=scope_state.acquisition;trace.queue_redraw()
		var measurement_lines: Array[String]=[]
		var config: Dictionary=trace.settings
		for i in 2:
			if not config.channels[i].enabled:
				measurement_lines.append("CH%d OFF"%(i+1));continue
			var stats: Dictionary=preload("res://scripts/dc_scope/measurements.gd").statistics(trace.visible_samples(),i,config.channels[i])
			if stats.count<2:
				measurement_lines.append("CH%d awaiting samples"%(i+1));continue
			measurement_lines.append("CH%d %.3f Vpp  %.3f Vrms · %s"%[i+1,float(stats.vpp),float(stats.rms),"%.2f Hz"%float(stats.frequency) if stats.frequency_valid else "— Hz"])
		scope_metrics.text="%s s/div · %s V/div / %s V/div\n%s"%[str(config.timebase),str(config.channels[0].scale),str(config.channels[1].scale),"  |  ".join(measurement_lines)]
		var warning := str(state.get("scope_probe",{}).get("warning",""))
		if not result.get("ok",true):warning="Solve failed · last acquired record"
		if not warning.is_empty():scope_metrics.text+="\n"+warning
		viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
		last_state=scope_state.duplicate(true)

func _update_hover() -> void:
	if is_instance_valid(hovered):hovered.hide()
	var camera: Camera3D=binding.lab.game.camera
	var query := PhysicsRayQueryParameters3D.create(camera.global_position,camera.global_position-camera.global_basis.z*3.6,1)
	var hit := physical.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():return
	var target: Node=hit.collider
	if int(target.get_meta("dc_station",-1))!=binding.station:return
	hovered=target.get_meta("dc_hover_visual",null)
	if is_instance_valid(hovered):hovered.show()
