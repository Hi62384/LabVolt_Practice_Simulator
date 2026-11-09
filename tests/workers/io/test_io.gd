extends SceneTree
const D=preload("res://scripts/io_devices/devices.gd")
const C=preload("res://scripts/io_devices/controls.gd")
const Catalog=preload("res://scripts/io_devices/catalog.gd")
const Surface=preload("res://scripts/io_devices/surface.gd")
const Physical=preload("res://scripts/io_devices/physical_surface.gd")
const Solver=preload("res://scripts/electronics_solver.gd")
const Replication=preload("res://scripts/io_devices/replication.gd")
const Adapter=preload("res://scripts/io_devices/host_adapter.gd")
var fails := 0
var checks := 0
func check(ok: bool,label: String) -> void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:fails+=1
func expansion(kind: String,n: Array,s: Dictionary={},c: Dictionary={},id: String="device") -> Array:
	return D.expand(Catalog.all()[kind],id,n,c,{}, {id:s})
func electrical(parts: Array) -> Array:return parts.filter(func(p):return p.kind!="io_device")
func source(id: String,a: String,b: String,value: float) -> Dictionary:return {"id":id,"kind":"V","a":a,"b":b,"value":value,"resistance":.01}
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	check(Catalog.all().size()==15,"15 representative modules, no replacement of existing devices")
	for kind in Catalog.all():
		var nodes: Array=[]
		for pin in Catalog.all()[kind].pins.size():nodes.append("n"+str(pin))
		var parts := expansion(kind,nodes)
		check(parts.size()>1 and parts[0].kind=="io_device",kind+" expands with descriptor and real primitives")
		check(Solver.new().solve(electrical(parts),[],.0005).ok,kind+" disconnected model solves without fake power")
	var old := C.defaults("io_encoder")
	var change := C.apply("io_encoder",old,{"op":"turn","steps":1,"revision":0})
	check(change.ok and old.detent==0 and change.state.detent==1,"control reducer immutable, bounded detents")
	check(not C.apply("io_encoder",change.state,{"op":"turn","steps":1,"revision":0}).ok,"stale simultaneous control rejected")
	check(not C.apply("io_slider",{}, {"op":"move","x":NAN,"revision":0}).ok,"nonfinite input rejected")
	check(Adapter.validate_controls({"board/s":{"x":.5}},{"board/s":"io_slider"})=="","optional saved input schema validates known device")
	check(Adapter.validate_controls({"board/s":{"x":INF}},{"board/s":"io_slider"})!="","optional saved input schema rejects invalid data")
	check(Adapter.validate_controls({"board/hidden":{}},{})!="","unknown instance controls cannot enter saved state")
	var phase := {};var sequence: Array=[]
	for step in 4:
		var parts := expansion("io_encoder",["a","b","g"],phase,change.state)
		phase=D.tick(parts[0],{"ok":true},phase,.0005);sequence.append(phase.phase)
	check(sequence==[1,2,3,4],"one-detent request queues all four quadrature phases")
	var contacts := expansion("io_encoder",["a","b","g"],{"phase":3})
	check(contacts[1].value>.1 and contacts[2].value==.01,"Gray phase 3 closes B only")
	var slider := expansion("io_slider",["v","w","g"],{}, {"x":.25})
	var p := electrical(slider);p.append(source("s","v","g",5.));var r := Solver.new().solve(p)
	check(r.ok and absf(D.voltage(r.v,"w","g")-1.25)<.001,"slider wiper solves at quarter of applied voltage")
	var stick := expansion("io_joystick",["v","x","y","g","sw","g"],{}, {"x":.2,"y":.8,"pressed":true})
	p=electrical(stick);p.append(source("s","v","g",5.));r=Solver.new().solve(p)
	check(r.ok and absf(D.voltage(r.v,"x","g")-1.)<.001 and absf(D.voltage(r.v,"y","g")-4.)<.001,"joystick axes share actual reference supply")
	var keys := C.apply("io_keypad",{}, {"op":"key","key":7,"pressed":true,"revision":0})
	var keypad := expansion("io_keypad",["r0","r1","r2","r3","c0","c1","c2"],{},keys.state)
	p=electrical(keypad);p.append(source("s","r2","g",5.));p.append({"id":"pull","kind":"R","a":"c1","b":"g","value":10000.});r=Solver.new().solve(p)
	check(r.ok and D.voltage(r.v,"c1","g")>4.99,"key 7 connects row 2 to column 1 electrically")
	var selector := expansion("io_selector",["v","o0","o1","o2"],{}, {"position":2})
	check(selector[1].value==1e12 and selector[3].value==.01,"selector changes only selected contact")
	var matrix := expansion("io_matrix",["r0","r1","r2","r3","k0","k1","k2","k3"])
	p=electrical(matrix);p.append(source("s","v","k2",5.));p.append({"id":"limit","kind":"R","a":"v","b":"r1","value":150.});r=Solver.new().solve(p)
	var matrix_state := D.tick(matrix[0],r,{},.0005)
	check(r.ok and matrix_state.levels[6]>.99 and matrix_state.levels[0]<.001,"matrix row/column wiring selects actual intersection current")
	var rgb := expansion("io_rgb",["r","gr","b","g"])
	p=electrical(rgb);p.append(source("s","v","g",5.));p.append({"id":"limit","kind":"R","a":"v","b":"r","value":150.});r=Solver.new().solve(p)
	var light := D.tick(rgb[0],r,{},.0005)
	check(r.ok and light.levels[0]>.99 and light.levels[1]<.001 and light.levels[2]<.001,"RGB brightness follows separately wired junction current")
	serial_tests()
	firmware_test()
	motor_tests()
	servo_tests()
	var relay := expansion("io_relay",["v","g","com","nc","no"])
	var pulled := D.tick(relay[0],{"ok":true,"v":{"v":5.,"g":0.}}, {},.0005)
	var released := D.tick(relay[0],{"ok":true,"v":{"v":1.,"g":0.}},pulled,.0005)
	check(pulled.closed and not released.closed,"relay coil threshold and release hysteresis")
	var driver := expansion("io_bridge",["v","g","in1","in2","a","b"],{"powered":true})
	p=D.expand(Catalog.all().io_bridge,"device",["v","g","in1","in2","a","b"],{}, {"v":5.,"g":0.,"in1":5.,"in2":0.},{"device":{"powered":true}})
	p=electrical(p);p.append(source("s","v","g",5.));p.append({"id":"load","kind":"R","a":"a","b":"b","value":20.});r=Solver.new().solve(p)
	check(r.ok and D.voltage(r.v,"a","b")>4.1 and float(r.i.load)>.2,"H bridge supplies actual load through finite-resistance power paths")
	var a := Surface.new();var b := Physical.new();root.add_child(a);root.add_child(b)
	a.size=Vector2(256,256);a.present("io_rgb",light);b.present("io_rgb",light)
	check(a.live==b.surface.live,"2D and physical renderer consume identical state")
	var sent: Array=[]
	a.command_requested.connect(func(command):sent.append(command))
	a.present("io_keypad",{"control":{"revision":0,"keys":0}})
	a.submit({"op":"key","key":1,"pressed":true});a.submit({"op":"key","key":1,"pressed":false})
	check(sent.size()==1,"release waits for host press acknowledgment under latency")
	a.acknowledge({"revision":1,"keys":2})
	check(sent.size()==2 and sent[1].revision==1 and not sent[1].pressed,"release uses the host's latest revision after acknowledgment")
	a.queue_free();b.queue_free()
	print("IO CHECKS: ",checks," FAILURES: ",fails);quit(fails)

func serial_byte(kind: String,n: Array,state: Dictionary,byte: int) -> Dictionary:
	var s := state
	for bit in range(7,-1,-1):
		for clock in [0.,5.]:
			var v := {"v":5.,"g":0.,"data":5. if byte&(1<<bit) else 0.,"clk":clock,"cs":0.}
			s=D.tick(expansion(kind,n,s)[0],{"ok":true,"v":v},s,.0005)
	return s
func serial_tests() -> void:
	var n: Array=["v","g","data","clk","cs"]
	var s := serial_byte("io_graphic",n,{},0)
	s=serial_byte("io_graphic",n,s,129);s=serial_byte("io_graphic",n,s,66)
	check(s.cells[0]==129 and s.cells[1]==66,"graphic framebuffer comes from clocked electrical serial bytes")
	var restored: Dictionary=JSON.parse_string(JSON.stringify(s))
	var equal: bool=restored.cells.size()==s.cells.size()
	for index in s.cells.size():equal=equal and int(restored.cells[index])==int(s.cells[index])
	check(equal,"late-join/save JSON roundtrip preserves framebuffer")
	var blank := D.tick(expansion("io_graphic",n,s)[0],{"ok":true,"v":{}},s,.0005)
	check(not blank.powered and not blank.has("cells"),"graphic power loss clears volatile display memory")
	s=serial_byte("io_pixels",n,{},2)
	s=serial_byte("io_pixels",n,s,255);s=serial_byte("io_pixels",n,s,128)
	check(s.pixels[6]==0,"RGB strip does not latch partial RGB packet")
	s=serial_byte("io_pixels",n,s,64)
	check(s.pixels[6]==255 and s.pixels[7]==128 and s.pixels[8]==64 and s.pixels[0]==0,"RGB pixel address and full RGB latch are electrically decoded")
	var load := expansion("io_pixels",n,s)
	check(load[1].value<500.,"addressable LED brightness increases actual supply loading")
	var frozen := D.tick(load[0],{"ok":false},s,.0005)
	check(frozen==s,"failed solve never advances a display or manufactures readings")
	var published := {"board/screen":Replication.public_state("io_pixels",s)}
	check(Replication.delta(published,published).changed.is_empty(),"unchanged screen does not retransmit framebuffer")
	var received := Replication.apply_delta({},Replication.delta({},published))
	check(received==published,"late client applies full device publication")
	check(Replication.apply_delta(received,Replication.delta(published,{})).is_empty(),"removing a device removes remote rendered state")

func firmware_test() -> void:
	var runtime := preload("res://scripts/firmware_runtime.gd").new()
	var code := "mode D0 out\nmode D1 out\nmode PWM out\nwrite PWM 0\n"
	for byte in [0,165,90]:
		for bit in range(7,-1,-1):code+="write D1 0\nwrite D0 %d\nwait 1\nwrite D1 1\nwait 1\n"%((byte>>bit)&1)
	code+="write PWM 1\nhalt"
	var solver := Solver.new();var cpu := {};var display := {};var result := {}
	var n: Array=["v","g","data","clk","cs"]
	for step in 600:
		cpu=runtime.tick(code,["v","g","data","clk","adc","cs"],result.get("v",{}),.0005,true)
		var primitive := preload("res://scripts/device_models.gd").expand({"kind":"controller"},"cpu",["v","g","data","clk","adc","cs"],{"firmware":code},result.get("v",{}),{"cpu":cpu}).filter(func(p):return p.kind!="controller")
		var expanded := expansion("io_graphic",n,display)
		primitive.append_array(electrical(expanded));primitive.append(source("power","v","g",5.))
		result=solver.solve(primitive,[],.0005)
		display=D.tick(expanded[0],result,display,.0005)
	check(result.get("ok",false) and display.get("cells",[]).size()==32 and display.cells[0]==165 and display.cells[1]==90,"existing LV firmware execution drives graphic framebuffer through solved wires")
	var first := expansion("io_graphic",n,{}, {},"board/pcb/inner/display")
	var second := expansion("io_graphic",n,{}, {},"board/pcb2/inner/display")
	check(first[1].id!=second[1].id and first[0].id=="board/pcb/inner/display","nested globally qualified device identities remain distinct")

func motor_tests() -> void:
	var solver := Solver.new();var s := {};var r := {};var first := 0.
	for step in 1600:
		var expanded := expansion("io_motor",["v","g"],s)
		var p := electrical(expanded);p.append(source("s","v","g",5.))
		r=solver.solve(p,[],.0005)
		if not r.ok:break
		if step==0:first=float(r.i["device/winding"])
		s=D.tick(expanded[0],r,s,.0005)
	check(r.get("ok",false) and float(s.get("omega",0))>100. and float(r.i["device/winding"])<first*.6,"DC motor accelerates and back EMF reduces winding current")
	# Equilibrium: kt*(V-ke*w)/R = friction*w -> w=125 rad/s.
	check(absf(float(s.get("omega",0))-125.)<6.,"motor equilibrium matches independently calculated 125 rad/s")
	var open := expansion("io_motor",["v","g"],s)
	r=solver.solve(electrical(open),[],.0005)
	var coast := D.tick(open[0],r,s,.0005)
	check(r.ok and coast.omega<s.omega,"disconnected motor coasts down with no applied torque")
	var vibration := D.tick(expansion("io_vibration",["v","g"])[0],{"ok":true,"i":{"device/winding":.1}}, {},.0005)
	check(vibration.force>0,"eccentric motor produces speed-dependent vibration force")

func servo_tests() -> void:
	var s := {};var n: Array=["v","g","signal"]
	for step in 240:
		var v := {"v":5.,"g":0.,"signal":5. if step%40<4 else 0.}
		s=D.tick(expansion("io_servo",n,s)[0],{"ok":true,"v":v},s,.0005)
	check(s.get("signal_valid",false) and s.get("target",0)>179 and s.get("angle",90)>100.,"servo decodes 2 ms/20 ms electrical pulses and rate-limits motion")
	for step in 150:s=D.tick(expansion("io_servo",n,s)[0],{"ok":true,"v":{"v":5.,"g":0.,"signal":5.}},s,.0005)
	check(not s.signal_valid,"constant high is not a fabricated servo position")
