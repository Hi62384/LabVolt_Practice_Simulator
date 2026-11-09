extends Node3D
## Front-facing DC instruments. Parent coordinates match dc_lab bench origin.
## Every control sends the existing host-validated action through dc_lab.request.
const MODEL := "res://assets/instruments/physical/"
var lab: Node
var station := -1
var readouts := {}
var controls := {}
var last_signature := ""
var clock := 0.0

func build(owner: Node, index: int) -> void:
	lab=owner; station=index
	_device("supply",Vector3(-1.39,1.37,-.18))
	_device("meter",Vector3(-.12,1.55,-.18))
	_device("generator",Vector3(-.12,1.13,-.18))
	_device("scope",Vector3(1.30,1.36,-.18))
	_device("patchdeck",Vector3(0,.985,.34))
	for i in 3:
		var x := -1.39+(i-1)*.45
		_readout("s%d"%i,Vector3(x,1.54,-.165),.034,Color("a6f3d6"))
		_knob(Vector3(x,1.23,-.149),{"op":"channel","index":i,"key":"voltage"},"CH%d voltage"%(i+1))
		_port("CH%d+"%(i+1),Vector3(x-.10,1.10,-.11),Color("e4564e"))
		_port("CH%d-"%(i+1),Vector3(x+.10,1.10,-.11),Color("24292c"))
	_readout("meter",Vector3(-.30,1.58,-.157),.036,Color("f0f4d7"))
	_readout("generator",Vector3(-.28,1.17,-.157),.030,Color("a6f3d6"))
	_readout("scope",Vector3(1.20,1.43,-.157),.031,Color("8be3d8"))
	_button(Vector3(-.12,1.42,-.15),{"op":"meter_mode_next"},"Meter mode")
	_button(Vector3(.11,1.42,-.15),{"op":"meter_range_next"},"Meter range")
	_button(Vector3(-.12,1.00,-.15),{"op":"generator","key":"enabled"},"Generator output")
	_knob(Vector3(.15,1.00,-.15),{"op":"generator","key":"frequency"},"Generator frequency")
	_button(Vector3(-1.39,1.68,-.15),{"op":"master"},"Master output")
	_button(Vector3(1.64,1.08,-.15),{"op":"scope","key":"running"},"Scope run / stop")
	_open_panel(Vector3(1.05,1.08,-.15))
	for source_index in 4:
		_button(Vector3(-1.65+source_index*.50,1.073,.54),{"op":"current_source","index":source_index,"key":"enabled"},"Current source %d"%(source_index+1))
	for id in ["VΩ","COM","A","GEN","REF","S1","S2","GND"]:
		var n := ["VΩ","COM","A","GEN","REF","S1","S2","GND"].find(id)
		_port(id,Vector3(-1.82+n*.52,.985,.52),Color("d84b45") if id in ["VΩ","A","GEN"] else Color("273137"))
	# Patch bank holds current sources and passive components; no terminal ID changes.
	var bank := ["IS+","IS-","IS2+","IS2-","IS3+","IS3-","IS4+","IS4-","R1a","R1b","R2a","R2b","Ca","Cb","Da","Db","B1","B2","B3","B4"]
	for n in bank.size():
		_port(bank[n],Vector3(-1.98+(n%10)*.44,.91 if n<10 else .84,.56),Color("c46554") if bank[n].ends_with("+") or bank[n].ends_with("a") else Color("2a363a"))

func _device(kind: String, at: Vector3) -> void:
	var mesh := load(MODEL+kind+".obj")
	if mesh == null:return
	var body := MeshInstance3D.new();body.mesh=mesh;body.position=at;add_child(body)

func _readout(id: String,at: Vector3,size: float,tint: Color) -> void:
	var label := Label3D.new();label.position=at;label.font_size=48;label.pixel_size=size/48.0
	label.modulate=tint;label.no_depth_test=false;add_child(label);readouts[id]=label

func _control(at: Vector3,action: Dictionary,title: String,shape: Shape3D,model: String) -> void:
	var body := StaticBody3D.new();body.position=at;body.set_meta("role","dc_instrument_control")
	body.set_meta("dc_station",station);body.set_meta("action",action);body.set_meta("label",title);add_child(body)
	var collision := CollisionShape3D.new();collision.shape=shape;body.add_child(collision)
	var visual := MeshInstance3D.new();visual.mesh=load(MODEL+model+".obj");body.add_child(visual)
	controls[title]=body

func _button(at: Vector3,action: Dictionary,title: String) -> void:
	var shape := BoxShape3D.new();shape.size=Vector3(.085,.045,.065)
	_control(at,action,title,shape,"button")
func _open_panel(at: Vector3) -> void:
	var body := StaticBody3D.new();body.position=at;body.set_meta("role","dc_panel")
	body.set_meta("dc_station",station);body.set_meta("label","Instrument settings")
	var shape := BoxShape3D.new();shape.size=Vector3(.12,.06,.05)
	var collision := CollisionShape3D.new();collision.shape=shape;body.add_child(collision);add_child(body)
	var visual := MeshInstance3D.new();visual.mesh=load(MODEL+"button.obj");body.add_child(visual)
func _knob(at: Vector3,action: Dictionary,title: String) -> void:
	var shape := SphereShape3D.new();shape.radius=.046
	_control(at,action,title,shape,"knob")
func _port(id: String,at: Vector3,tint: Color) -> void:
	var body := StaticBody3D.new();body.position=at;body.set_meta("role","dc_port")
	body.set_meta("dc_station",station);body.set_meta("dc_port",id);body.set_meta("label",id);add_child(body)
	var shape := SphereShape3D.new();shape.radius=.045
	var collision := CollisionShape3D.new();collision.shape=shape;body.add_child(collision)
	var ring := MeshInstance3D.new();ring.mesh=load(MODEL+"socket.obj")
	var mat := StandardMaterial3D.new();mat.albedo_color=tint;ring.material_override=mat;body.add_child(ring)
	var legend := Label3D.new();legend.text=id;legend.position=Vector3(0,.055,.003)
	legend.pixel_size=.00055;legend.font_size=48;legend.modulate=Color("eef1e9")
	body.add_child(legend)

func port_positions() -> Dictionary:
	var result := {}
	for child in get_children():
		if child.get_meta("role","")=="dc_port":result[str(child.get_meta("dc_port"))]=child.global_position+child.global_basis.z*.04
	return result

func action_for(target: Node,right: bool,state: Dictionary) -> Dictionary:
	if right:return {}
	var action: Dictionary=target.get_meta("action",{}).duplicate()
	match str(action.get("op","")):
		"channel":
			var i: int=action.index
			action.value=clampf(float(state.channels[i].voltage)+.1,0,30)
		"generator":
			if action.key=="enabled":action.value=not bool(state.generator.enabled)
			else:action.value=clampf(float(state.generator.frequency)+.1,.1,100)
		"meter_mode_next":
			var modes := ["DC V","AC V","DC A","AC A","Resistance","Continuity","Diode","Capacitance","Frequency","Duty"]
			action={"op":"meter","mode":modes[(modes.find(str(state.meter_mode))+1)%modes.size()]}
		"meter_range_next":
			var ranges := [0.0,.0002,.002,.02,.2,2.0,20.0,200.0]
			action={"op":"meter_range","value":ranges[(ranges.find(float(state.meter_range))+1)%ranges.size()]}
		"current_source":
			action.value=not bool(state.current_sources[int(action.index)].enabled)
		"scope":
			action.value=not bool(state.scope.get("running",false))
	return action

func observe(state: Dictionary,delta: float,relevant: bool) -> void:
	clock+=delta
	if not relevant or clock<.1:return
	clock=0
	var result: Dictionary=state.get("result",{})
	for i in 3:
		var id := "s%d"%i
		var voltage := float(result.get("drop",{}).get(id,0))
		var current := -float(result.get("i",{}).get(id,0))
		readouts[id].text="%05.2f V\n%06.3f A\n%06.2f W"%[voltage,current,voltage*current]
	readouts.meter.text=str(state.get("meter","—"))
	var generator: Dictionary=state.get("generator",{})
	readouts.generator.text="%s  %.1f Hz\n%.2f Vpk"%[str(generator.get("wave","Sine")),float(generator.get("frequency",0)),float(generator.get("amplitude",0))]
	var scope: Dictionary=state.get("scope",{})
	readouts.scope.text="CH1   CH2\n%s   %.3f s/div"%["RUN" if scope.get("running",false) else "STOP",float(scope.get("timebase",.01))]
