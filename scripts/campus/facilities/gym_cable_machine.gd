extends Node3D
## Mechanical visual: the cable is rebuilt between fixed pulleys and the moving grip.
var station_id: String
var occupant:=0
var target_phase:=0.0
var phase:=0.0
var exercise:=""
var selected:=1
var handle: Node3D
var second_handle: Node3D
var cable: MeshInstance3D
var second_cable: MeshInstance3D
var routed_cable: MeshInstance3D
var second_routed_cable: MeshInstance3D
var route_sections: Array[MeshInstance3D]=[]
var second_route_sections: Array[MeshInstance3D]=[]
var stack_cable: MeshInstance3D
var raised_stack: Node3D
var weights: Array[MeshInstance3D]=[]
var selection_pin: MeshInstance3D
var pin_targets: Array[StaticBody3D]=[]
var dark: StandardMaterial3D
var steel: StandardMaterial3D
var left_hand: Node3D
var right_hand: Node3D

func build(id: String) -> void:
	station_id=id;dark=_material(Color("26363d"),.85,.15);steel=_material(Color("728891"),.45,.6)
	for x in [-.54,.54]:
		_box(self,Vector3(x,1.22,0),Vector3(.11,2.44,.12),steel)
		_box(self,Vector3(x,.08,.12),Vector3(.20,.16,1.10),dark)
	_box(self,Vector3(0,2.40,0),Vector3(1.20,.12,.15),steel)
	_box(self,Vector3(0,1.1,-.15),Vector3(.64,2.05,.25),dark)
	for x in [-.26,.26]:_box(self,Vector3(x,1.0,.08),Vector3(.025,1.9,.025),steel)
	for i in 20:
		var plate:=_box(self,Vector3(0,.16+i*.075,.10),Vector3(.48,.065,.22),steel)
		weights.append(plate)
		var pin_target:=StaticBody3D.new();pin_target.name="CableWeightPin_%d" % ((i+1)*5)
		pin_target.position=Vector3(.31,.16+i*.075,.30);pin_target.collision_layer=4;pin_target.collision_mask=0
		pin_target.set_meta("role","gym_cable_pin");pin_target.set_meta("station",id);pin_target.set_meta("weight",(i+1)*5)
		pin_target.set_meta("label","Set cable resistance to %d kg" % ((i+1)*5))
		var pin_hit:=CollisionShape3D.new();var pin_shape:=BoxShape3D.new();pin_shape.size=Vector3(.28,.085,.30);pin_hit.shape=pin_shape;pin_target.add_child(pin_hit);add_child(pin_target);pin_targets.append(pin_target)
	selection_pin=_box(self,Vector3(.25,.16,.25),Vector3(.30,.07,.12),_material(Color("cfad63"),.5,.35))
	raised_stack=Node3D.new();raised_stack.name="SelectedStack";add_child(raised_stack)
	var pulley:=MeshInstance3D.new();var wheel:=CylinderMesh.new();wheel.top_radius=.12;wheel.bottom_radius=.12;wheel.height=.07;wheel.radial_segments=16
	pulley.mesh=wheel;pulley.material_override=dark;pulley.rotation.z=PI/2;pulley.position=Vector3(0,2.3,.13);add_child(pulley)
	var lower_pulley:=MeshInstance3D.new();lower_pulley.mesh=wheel;lower_pulley.material_override=dark
	lower_pulley.rotation.z=PI/2;lower_pulley.position=Vector3(0,.20,.13);add_child(lower_pulley)
	handle=Node3D.new();handle.position=Vector3(0,1.45,.72);add_child(handle)
	_box(handle,Vector3.ZERO,Vector3(.52,.05,.05),steel)
	for x in [-.26,.26]:_box(handle,Vector3(x,-.08,0),Vector3(.05,.20,.05),dark)
	second_handle=handle.duplicate() as Node3D;add_child(second_handle);second_handle.hide()
	cable=MeshInstance3D.new();var wire:=CylinderMesh.new();wire.top_radius=.012;wire.bottom_radius=.012;wire.height=1.0;wire.radial_segments=8;cable.mesh=wire;cable.material_override=dark;add_child(cable)
	second_cable=MeshInstance3D.new();second_cable.mesh=wire;second_cable.material_override=dark;add_child(second_cable);second_cable.hide()
	routed_cable=MeshInstance3D.new();routed_cable.mesh=wire;routed_cable.material_override=dark;add_child(routed_cable);routed_cable.hide()
	second_routed_cable=MeshInstance3D.new();second_routed_cable.mesh=wire;second_routed_cable.material_override=dark;add_child(second_routed_cable);second_routed_cable.hide()
	for i in 4:
		var section:=MeshInstance3D.new();section.mesh=wire;section.material_override=dark;add_child(section);section.hide();route_sections.append(section)
		var second:=MeshInstance3D.new();second.mesh=wire;second.material_override=dark;add_child(second);second.hide();second_route_sections.append(second)
	stack_cable=MeshInstance3D.new();stack_cable.name="StackCable";stack_cable.mesh=wire;stack_cable.material_override=dark;add_child(stack_cable)
	var target:=StaticBody3D.new();target.collision_layer=4;target.collision_mask=0;target.set_meta("role","gym_equipment");target.set_meta("station",id);add_child(target)
	var hit:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(1.25,2.5,.34);hit.shape=shape;hit.position=Vector3(0,1.25,.04);target.add_child(hit)
	var solid:=StaticBody3D.new();solid.collision_layer=1;solid.collision_mask=0;add_child(solid)
	var solid_hit:=CollisionShape3D.new();var solid_shape:=BoxShape3D.new();solid_shape.size=Vector3(1.16,2.4,.22);solid_hit.shape=solid_shape;solid_hit.position=Vector3(0,1.2,-.18);solid.add_child(solid_hit)
	# The steel frame, feet and top crossbar are solid too; the ray target above
	# remains separate so the player can still interact with the full machine.
	for x in [-.54,.54]:
		_add_solid_box(solid,Vector3(x,1.22,0),Vector3(.11,2.44,.12))
		_add_solid_box(solid,Vector3(x,.08,.12),Vector3(.20,.16,1.10))
	_add_solid_box(solid,Vector3(0,2.40,0),Vector3(1.20,.12,.15))
	_update_pin();_update_wire();set_process(false)

func selected_resistance() -> int:
	return clampi(selected,1,20)*5

func set_resistance(weight_kg: int) -> void:
	selected=clampi(roundi(float(weight_kg)/5.0),1,20)
	_update_pin()

func _update_pin() -> void:
	var index:=clampi(selected,1,20)-1
	if is_instance_valid(selection_pin):selection_pin.position.y=.16+float(index)*.075
	for i in pin_targets.size():pin_targets[i].set_meta("selected",i==index)

func on_room_event(peer: int,event: Dictionary, avatar: Node3D=null) -> void:
	if event.get("activity","")=="exercise" and event.get("station","")==station_id:
		occupant=peer;exercise=str(event.get("exercise",""));target_phase=float(event.get("phase",0))
		if is_instance_valid(avatar):
			left_hand=_avatar_hand(avatar,"ArmL")
			right_hand=_avatar_hand(avatar,"ArmR")
		set_resistance(int(event.get("weight",5)))
		set_process(true)
	elif peer==occupant and event.get("activity","")!="exercise":
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
	handle.position=Vector3(0,grip_y,.55+phase*.42)
	var dual:=occupant!=0 and exercise in ["cable_press","cable_fly","cable_reverse_fly","lateral_raise","front_raise","overhead_extension"]
	handle.scale=Vector3(.20,1,1) if dual else Vector3.ONE
	second_handle.visible=dual;second_cable.visible=dual
	if dual:
		handle.position.x=-.26
		second_handle.position=handle.position+Vector3(.52,0,0)
		second_handle.scale=handle.scale
	if occupant!=0 and is_instance_valid(left_hand) and is_instance_valid(right_hand):
		if dual:
			handle.global_position=left_hand.global_position
			second_handle.global_position=right_hand.global_position
		else:handle.global_position=(left_hand.global_position+right_hand.global_position)*.5
	for i in weights.size():weights[i].position.y=.16+i*.075+(.24*phase if i>=weights.size()-selected else 0.0)
	_update_wire()
	if occupant==0 and is_zero_approx(phase):set_process(false)

func _update_wire() -> void:
	var low:=occupant!=0 and exercise in ["curl","front_raise","lateral_raise","overhead_press"]
	var pulley:=Vector3(0,.20,.13) if low else Vector3(0,2.3,.13)
	var around_player:=occupant!=0 and exercise in ["cable_press","cable_fly","overhead_extension"]
	routed_cable.visible=around_player
	second_routed_cable.visible=around_player and second_cable.visible
	for section in route_sections:section.visible=around_player
	for section in second_route_sections:section.visible=around_player and second_cable.visible
	if around_player:
		_route_cable(cable,routed_cable,route_sections,pulley,handle.position,-1.0)
		if second_cable.visible:_route_cable(second_cable,second_routed_cable,second_route_sections,pulley,second_handle.position,1.0)
	else:
		_position_cable(cable,pulley,handle.position)
		if second_cable.visible:_position_cable(second_cable,pulley,second_handle.position)
	# The pin lifts the selected upper stack, so its top attachment follows it.
	_position_cable(stack_cable,Vector3(0,2.3,.13),Vector3(0,.16+(weights.size()-1)*.075+.035+.24*phase,.10))

func _route_cable(first: MeshInstance3D,last: MeshInstance3D,sections: Array[MeshInstance3D],pulley: Vector3,grip: Vector3,fallback_side: float) -> void:
	# Chest movements face away from the pulley. Keep the lead outside the
	# avatar's shoulders, using a smooth curve back to the grip.
	var side:=signf(grip.x) if absf(grip.x)>.01 else fallback_side
	var offset:=side*maxf(.90,absf(grip.x)+.40)
	var control_a:=Vector3(offset,2.0,.65)
	var control_b:=Vector3(offset,maxf(1.0,grip.y),maxf(1.42,grip.z-.1))
	var segments: Array[MeshInstance3D]=[first]
	segments.append_array(sections);segments.append(last)
	var previous:=pulley
	for i in segments.size():
		var t:=float(i+1)/float(segments.size());var u:=1.0-t
		var point:=u*u*u*pulley+3.0*u*u*t*control_a+3.0*u*t*t*control_b+t*t*t*grip
		_position_cable(segments[i],previous,point);previous=point

func _position_cable(segment: MeshInstance3D,a: Vector3,b: Vector3) -> void:
	var axis:=b-a
	segment.position=(a+b)*.5
	if axis.length_squared()<.000001:
		segment.hide();return
	segment.show()
	var cable_basis:=Basis(Quaternion(Vector3.UP,axis.normalized()))
	cable_basis.y=axis
	segment.basis=cable_basis

func _box(parent: Node3D,at: Vector3,size: Vector3,material: Material) -> MeshInstance3D:
	var mesh:=BoxMesh.new();mesh.size=size
	var part:=MeshInstance3D.new();part.mesh=mesh;part.position=at;part.material_override=material;parent.add_child(part);return part

func _add_solid_box(parent: StaticBody3D,at: Vector3,size: Vector3) -> void:
	var hit:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;hit.shape=shape;hit.position=at;parent.add_child(hit)

func _material(color: Color,roughness: float,metallic: float) -> StandardMaterial3D:
	var result:=StandardMaterial3D.new();result.albedo_color=color;result.roughness=roughness;result.metallic=metallic;return result
