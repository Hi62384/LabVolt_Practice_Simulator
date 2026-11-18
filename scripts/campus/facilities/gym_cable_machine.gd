extends Node3D
## Mechanical visual: the cable is rebuilt between fixed pulleys and the moving grip.
var station_id: String
var occupant:=0
var target_phase:=0.0
var phase:=0.0
var exercise:=""
var return_from := Transform3D.IDENTITY
var return_second := Transform3D.IDENTITY
var return_elapsed := 0.0
var return_duration := 0.0
var return_dual := false
var selected:=1
var handle: Node3D
var second_handle: Node3D
var single_grip: Node3D
var long_grip: Node3D
var loading_mount: Node3D
const PLATE_LIMIT := 3
const PLATE_SPACING := .092
var cable: MeshInstance3D
var second_cable: MeshInstance3D
var routed_cable: MeshInstance3D
var second_routed_cable: MeshInstance3D
var route_sections: Array[MeshInstance3D]=[]
var second_route_sections: Array[MeshInstance3D]=[]
var stack_cable: MeshInstance3D
var weights: Array[MeshInstance3D]=[]
var selection_pin: MeshInstance3D
const PIN_X := .15
const PIN_FRONT := .226
const HANDLE_REST := Vector3(0, 2.035, .39)
const TETHER_ANCHOR := Vector3(.28, 1.46, .23)
var tether: Array[MeshInstance3D] = []
const SIDE_GUIDE := Vector3(.86, 1.42, .48)
var pin_targets: Array[StaticBody3D]=[]
var highlighted_pin: MeshInstance3D
var dark: StandardMaterial3D
var steel: StandardMaterial3D
var left_hand: Node3D
var right_hand: Node3D

func build(id: String) -> void:
	station_id=id;dark=_material(Color("26363d"),.85,.15);steel=_material(Color("728891"),.45,.6)
	for x in [-.54,.54]:
		_box(self,Vector3(x,1.22,0),Vector3(.11,2.44,.12),steel)
		_box(self,Vector3(x,.08,.12),Vector3(.20,.16,1.10),dark)
	_box(self,Vector3(0,2.40,.09),Vector3(1.85,.12,.25),steel)
	_box(self,Vector3(0,1.1,-.15),Vector3(.64,2.05,.25),dark)
	for x in [-.26,.26]:_box(self,Vector3(x,1.0,.08),Vector3(.025,1.9,.025),steel)
	for i in 20:
		var plate:=_box(self,Vector3(0,.16+i*.075,.10),Vector3(.48,.065,.22),steel)
		weights.append(plate)
		var kg := (20 - i) * 5
		var plate_label := TextMesh.new()
		plate_label.text = "%d lb" % roundi(kg*2.20462262)
		plate_label.pixel_size = .001
		plate_label.font_size = 38
		plate_label.depth = .001
		var marking := MeshInstance3D.new()
		marking.mesh = plate_label
		marking.material_override = _material(Color("e6edf0"), .85, 0)
		marking.position = Vector3(-.056, 0, .112)
		plate.add_child(marking)
		_cylinder(plate, Vector3(PIN_X, 0, .111), .018, .003, dark)
		var pin_target:=StaticBody3D.new();pin_target.name="CableWeightPin_%d" % kg
		pin_target.position=Vector3(PIN_X,.16+i*.075,PIN_FRONT+.02);pin_target.collision_layer=4;pin_target.collision_mask=0
		pin_target.set_meta("role","gym_cable_pin");pin_target.set_meta("station",id);pin_target.set_meta("weight",kg)
		pin_target.set_meta("label","Set to %d lb" % roundi(kg*2.20462262))
		var pin_hit:=CollisionShape3D.new();var pin_shape:=BoxShape3D.new();pin_shape.size=Vector3(.06,.065,.06);pin_hit.shape=pin_shape;pin_target.add_child(pin_hit);add_child(pin_target);pin_targets.append(pin_target)
	selection_pin = _cylinder(self, Vector3(PIN_X,.16,.254), .010, .09, steel)
	_cylinder(self, TETHER_ANCHOR, .025, .016, dark)
	# The knob is part of the pin assembly. Its transform follows the shaft.
	var knob := _cylinder(selection_pin, Vector3(0,.050,0), .025, .028, _material(Color("bb9657"),.56,.35))
	knob.rotation.x = 0
	_box(self, Vector3(0,1.99,.225), Vector3(.42,.055,.12), steel)
	for x in [-.17,.17]:
		_box(self, Vector3(x,2.007,.34), Vector3(.048,.022,.22), steel)
		_box(self, Vector3(x,2.035,.449), Vector3(.048,.075,.028), dark)
	loading_mount=Node3D.new()
	loading_mount.name="CableLoadingPost"
	loading_mount.position=Vector3(0,1.62,.38)
	add_child(loading_mount)
	_box(loading_mount,Vector3(0,0,-.13),Vector3(.32,.043,.42),steel)
	var post:=_cylinder(loading_mount,Vector3(0,.169,0),.050,.32,steel)
	post.rotation.x=0
	var load_target:=StaticBody3D.new()
	load_target.collision_layer=4;load_target.collision_mask=0
	load_target.set_meta("role","gym_cable_load");load_target.set_meta("station",id)
	loading_mount.add_child(load_target)
	_add_solid_box(load_target,Vector3(0,.17,0),Vector3(.14,.33,.12))
	highlighted_pin=MeshInstance3D.new()
	var highlight_ring:=TorusMesh.new()
	highlight_ring.inner_radius=.017;highlight_ring.outer_radius=.024
	highlight_ring.rings=12;highlight_ring.ring_segments=6
	highlighted_pin.mesh=highlight_ring
	highlighted_pin.material_override=_material(Color("e2b767"),.56,.2)
	highlighted_pin.rotation.x=PI*.5;add_child(highlighted_pin)
	highlighted_pin.hide()
	var pulley:=MeshInstance3D.new();var wheel:=CylinderMesh.new();wheel.top_radius=.12;wheel.bottom_radius=.12;wheel.height=.07;wheel.radial_segments=16
	pulley.mesh=wheel;pulley.material_override=dark;pulley.rotation.z=PI/2;pulley.position=Vector3(0,2.3,.13);add_child(pulley)
	var lower_pulley:=MeshInstance3D.new();lower_pulley.mesh=wheel;lower_pulley.material_override=dark
	lower_pulley.rotation.z=PI/2;lower_pulley.position=Vector3(0,.20,.13);add_child(lower_pulley)

	for side in [-1.0, 1.0]:
		var guide := SIDE_GUIDE * Vector3(side, 1, 1)
		_box(self, Vector3(guide.x, .71, .26), Vector3(.12, 1.42, .14), steel)
		_box(self, Vector3(guide.x, .06, .26), Vector3(.26, .12, .64), dark)
		_box(self, guide - Vector3(0, 0, .09), Vector3(.18, .21, .26), dark)
		var roller := MeshInstance3D.new()
		roller.mesh = wheel
		roller.material_override = steel
		roller.scale = Vector3.ONE * .58
		roller.rotation.z = PI * .5
		roller.position = guide
		add_child(roller)
		var overhead := MeshInstance3D.new()
		overhead.mesh = wheel
		overhead.material_override = dark
		overhead.scale = Vector3.ONE * .57
		overhead.rotation.x = PI * .5
		overhead.position = Vector3(guide.x, 2.30, .13)
		add_child(overhead)
	handle=Node3D.new();handle.position=HANDLE_REST;add_child(handle)
	long_grip=_build_grip(handle,.52)
	single_grip=_build_grip(handle,.125)
	single_grip.hide()
	second_handle=Node3D.new();add_child(second_handle);_build_grip(second_handle,.125);second_handle.hide()
	cable=MeshInstance3D.new();var wire:=CylinderMesh.new();wire.top_radius=.012;wire.bottom_radius=.012;wire.height=1.0;wire.radial_segments=8;cable.mesh=wire;cable.material_override=dark;add_child(cable)
	second_cable=MeshInstance3D.new();second_cable.mesh=wire;second_cable.material_override=dark;add_child(second_cable);second_cable.hide()
	routed_cable=MeshInstance3D.new();routed_cable.mesh=wire;routed_cable.material_override=dark;add_child(routed_cable);routed_cable.hide()
	second_routed_cable=MeshInstance3D.new();second_routed_cable.mesh=wire;second_routed_cable.material_override=dark;add_child(second_routed_cable);second_routed_cable.hide()
	for i in 1:
		var section:=MeshInstance3D.new();section.mesh=wire;section.material_override=dark;add_child(section);section.hide();route_sections.append(section)
		var second:=MeshInstance3D.new();second.mesh=wire;second.material_override=dark;add_child(second);second.hide();second_route_sections.append(second)
	stack_cable=MeshInstance3D.new();stack_cable.name="StackCable";stack_cable.mesh=wire;stack_cable.material_override=dark;add_child(stack_cable)
	for index in 2:
		var line := MeshInstance3D.new()
		line.mesh = wire
		line.material_override = steel
		line.scale = Vector3(.32, 1, .32)
		tether.append(line)
		add_child(line)
	var target := StaticBody3D.new()
	target.collision_layer=4
	target.collision_mask=0
	target.position=Vector3(0,2.05,.27)
	target.set_meta("role","gym_equipment")
	target.set_meta("station",id)
	target.set_meta("label","Open cable exercises")
	add_child(target)
	_add_solid_box(target,Vector3.ZERO,Vector3(1.00,.22,.27))
	var solid:=StaticBody3D.new();solid.collision_layer=1;solid.collision_mask=0;add_child(solid)
	var solid_hit:=CollisionShape3D.new();var solid_shape:=BoxShape3D.new();solid_shape.size=Vector3(1.16,2.4,.22);solid_hit.shape=solid_shape;solid_hit.position=Vector3(0,1.2,-.18);solid.add_child(solid_hit)
	# The steel frame, feet and top crossbar are solid too; the ray target above
	# remains separate so the player can still interact with the full machine.
	for x in [-.54,.54]:
		_add_solid_box(solid,Vector3(x,1.22,0),Vector3(.11,2.44,.12))
		_add_solid_box(solid,Vector3(x,.08,.12),Vector3(.20,.16,1.10))
	_add_solid_box(solid,Vector3(0,2.40,.09),Vector3(1.85,.12,.25))
	for side in [-1.0, 1.0]:
		_add_solid_box(solid, Vector3(SIDE_GUIDE.x * side, .71, .26), Vector3(.12, 1.42, .14))
		_add_solid_box(solid, Vector3(SIDE_GUIDE.x * side, .06, .26), Vector3(.26, .12, .64))
	_update_pin();_update_wire();set_process(false)

func highlight_pin(target: Node3D) -> void:
	var active:=is_instance_valid(target) and target in pin_targets and occupant==0
	highlighted_pin.visible=active
	if active:highlighted_pin.position=target.position-Vector3(0,0,.032)

func selected_resistance() -> int:
	return clampi(selected,1,20)*5

func set_resistance(weight_kg: int) -> void:
	if weight_kg < 5 or weight_kg > 100 or weight_kg % 5 != 0:
		return
	selected=weight_kg/5
	_update_pin()

func _update_pin() -> void:
	var index := weights.size() - selected
	if is_instance_valid(selection_pin):
		selection_pin.position.y = weights[index].position.y
	for i in pin_targets.size():pin_targets[i].set_meta("selected",i==index)
	_update_tether()

func on_room_event(peer: int,event: Dictionary, avatar: Node3D=null) -> void:
	if event.get("activity","")=="exercise" and event.get("station","")==station_id:
		return_duration=0.0
		occupant=peer;exercise=str(event.get("exercise",""));target_phase=float(event.get("phase",0))
		if is_instance_valid(avatar):
			left_hand=_avatar_hand(avatar,"ArmL")
			right_hand=_avatar_hand(avatar,"ArmR")
		set_resistance(int(event.get("selector_weight", event.get("weight",5))))
		set_process(true)
	elif peer==occupant and event.get("activity","")!="exercise":
		return_from=handle.transform
		return_second=second_handle.transform
		return_elapsed=0.0
		return_duration=.55
		return_dual=second_handle.visible
		occupant=0;target_phase=0.0;left_hand=null;right_hand=null;set_process(true)

func _avatar_hand(avatar: Node3D,arm_name: String) -> Node3D:
	var arm:=avatar.find_child(arm_name,true,false)
	if arm==null:return null
	for child in arm.get_children():
		if child is Node3D and str(child.name).begins_with("Hand"):return child
	return null

func _process(delta: float) -> void:
	phase=move_toward(phase,target_phase,delta*1.2)
	var high:=exercise in ["lat_pulldown","tricep_pushdown","overhead_extension","cable_crunch"]
	var low:=exercise in ["curl","front_raise","lateral_raise","overhead_press"]
	var base_y:=1.75 if high else .62 if low else 1.30
	var grip_y:=base_y-phase*.48 if high else base_y+phase*.46 if low else base_y
	handle.position=HANDLE_REST if occupant==0 else Vector3(0,grip_y,.55+phase*.42)
	var dual:=occupant!=0 and exercise in ["cable_press","cable_fly","cable_reverse_fly","lateral_raise","front_raise","overhead_extension"]
	long_grip.visible=not dual;single_grip.visible=dual
	handle.basis=Basis.IDENTITY
	second_handle.visible=dual;second_cable.visible=dual
	if dual:
		handle.position.x=-.26
		second_handle.position=handle.position+Vector3(.52,0,0)
	if occupant!=0 and is_instance_valid(left_hand) and is_instance_valid(right_hand):
		if dual:
			handle.global_position=left_hand.global_position
			second_handle.global_position=right_hand.global_position
		else:
			var grip_delta:=to_local(right_hand.global_position)-to_local(left_hand.global_position)
			handle.global_position=(left_hand.global_position+right_hand.global_position)*.5
			if grip_delta.length_squared()>.001:
				if grip_delta.x<0:grip_delta=-grip_delta
				handle.basis=Basis(Quaternion(Vector3.RIGHT,grip_delta.normalized()))
	if occupant==0 and return_elapsed<return_duration:
		return_elapsed=minf(return_elapsed+delta,return_duration)
		var blend := smoothstep(0.0,return_duration,return_elapsed)
		handle.transform=return_from.interpolate_with(Transform3D(Basis.IDENTITY,HANDLE_REST),blend)
		second_handle.transform=return_second.interpolate_with(Transform3D(Basis.IDENTITY,HANDLE_REST),blend)
		second_handle.visible=return_dual and blend<1.0
		second_cable.visible=second_handle.visible
		single_grip.visible=second_handle.visible
		long_grip.visible=not second_handle.visible
	for grip in [handle,second_handle]:
		grip.set_meta("connector",grip.transform*Vector3(0,.113,0))
	loading_mount.position.y=1.62+.24*phase
	for i in weights.size():weights[i].position.y=.16+i*.075+(.24*phase if i>=weights.size()-selected else 0.0)
	selection_pin.position.y = weights[weights.size() - selected].position.y
	for i in pin_targets.size():
		pin_targets[i].position.y = weights[i].position.y
	_update_tether()
	_update_wire()
	if occupant==0 and is_zero_approx(phase) and return_elapsed>=return_duration:set_process(false)

func _build_grip(parent: Node3D, width: float) -> Node3D:
	var assembly:=Node3D.new()
	parent.add_child(assembly)
	var grip:=_cylinder(assembly,Vector3.ZERO,.026,width,steel)
	grip.rotation=Vector3(0,0,PI*.5)
	var sleeve:=_cylinder(assembly,Vector3.ZERO,.029,width*.75,dark)
	sleeve.rotation=Vector3(0,0,PI*.5)
	for side in [-1.0,1.0]:
		var start:=Vector3(side*width*.44,.016,0)
		var end:=Vector3(side*.023,.081,0)
		var strut:=_box(assembly,(start+end)*.5,Vector3(.016,start.distance_to(end)+.006,.017),steel)
		strut.basis=Basis(Quaternion(Vector3.UP,(end-start).normalized()))
	var connector:=MeshInstance3D.new()
	var loop:=TorusMesh.new()
	loop.inner_radius=.011;loop.outer_radius=.022;loop.rings=12;loop.ring_segments=8
	connector.mesh=loop;connector.material_override=steel;connector.rotation.x=PI*.5
	connector.position.y=.090;assembly.add_child(connector)
	return assembly

func position_local_grips(peer: int, left: Vector3, right: Vector3) -> void:
	if occupant!=peer:return
	if second_handle.visible:
		handle.global_position=left
		second_handle.global_position=right
	else:
		handle.global_position=(left+right)*.5
		var direction:=to_local(right)-to_local(left)
		if direction.length_squared()>.001:
			handle.basis=Basis(Quaternion(Vector3.RIGHT,direction.normalized()))
	for grip in [handle,second_handle]:
		grip.set_meta("connector",grip.transform*Vector3(0,.113,0))
	_update_wire()

func _update_wire() -> void:
	var low:=occupant!=0 and exercise in ["curl","front_raise","lateral_raise","overhead_press"]
	var pulley:=Vector3(0,.20,.13) if low else Vector3(0,2.3,.13)
	var around_player:=occupant!=0 and exercise in ["cable_press","cable_fly","overhead_extension"]
	routed_cable.visible=around_player
	second_routed_cable.visible=around_player and second_cable.visible
	for section in route_sections:section.visible=around_player
	for section in second_route_sections:section.visible=around_player and second_cable.visible
	if around_player:
		_route_cable(cable,routed_cable,route_sections,pulley,handle.get_meta("connector",handle.transform*Vector3(0,.113,0)),-1.0)
		if second_cable.visible:_route_cable(second_cable,second_routed_cable,second_route_sections,pulley,second_handle.get_meta("connector",second_handle.transform*Vector3(0,.113,0)),1.0)
	else:
		_position_cable(cable,pulley,handle.get_meta("connector",handle.transform*Vector3(0,.113,0)))
		if second_cable.visible:_position_cable(second_cable,pulley,second_handle.get_meta("connector",second_handle.transform*Vector3(0,.113,0)))
	# The pin lifts the selected upper stack, so its top attachment follows it.
	_position_cable(stack_cable,Vector3(0,2.3,.13),Vector3(0,.16+(weights.size()-1)*.075+.035+.24*phase,.10))

func _route_cable(first: MeshInstance3D,last: MeshInstance3D,sections: Array[MeshInstance3D],pulley: Vector3,grip: Vector3,fallback_side: float) -> void:
	var guide := SIDE_GUIDE * Vector3(fallback_side, 1, 1)
	var overhead_guide := Vector3(guide.x, pulley.y, pulley.z)
	_position_cable(first, pulley, overhead_guide)
	_position_cable(sections[0], overhead_guide, guide)
	_position_cable(last, guide, grip)

func _position_cable(segment: MeshInstance3D,a: Vector3,b: Vector3) -> void:
	var axis:=b-a
	segment.position=(a+b)*.5
	if axis.length_squared()<.000001:
		segment.hide();return
	segment.show()
	var cable_basis:=Basis(Quaternion(Vector3.UP,axis.normalized()))
	cable_basis.y=axis
	segment.basis=cable_basis

func _update_tether() -> void:
	var end := selection_pin.position + Vector3(0,0,.052)
	var sag := (TETHER_ANCHOR + end) * .5 + Vector3(.035,-.075,.050)
	_position_cable(tether[0], TETHER_ANCHOR, sag)
	_position_cable(tether[1], sag, end)
	for segment in tether:
		var axes := segment.basis
		segment.basis = Basis(axes.x*.32, axes.y, axes.z*.32)

func _cylinder(parent: Node3D, at: Vector3, radius: float, length: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 12
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.rotation.x = PI/2
	visual.position = at
	parent.add_child(visual)
	return visual

func _box(parent: Node3D,at: Vector3,size: Vector3,material: Material) -> MeshInstance3D:
	var mesh:=BoxMesh.new();mesh.size=size
	var part:=MeshInstance3D.new();part.mesh=mesh;part.position=at;part.material_override=material;parent.add_child(part);return part

func _add_solid_box(parent: StaticBody3D,at: Vector3,size: Vector3) -> void:
	var hit:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;hit.shape=shape;hit.position=at;parent.add_child(hit)

func _material(color: Color,roughness: float,metallic: float) -> StandardMaterial3D:
	var result:=StandardMaterial3D.new();result.albedo_color=color;result.roughness=roughness;result.metallic=metallic;return result
