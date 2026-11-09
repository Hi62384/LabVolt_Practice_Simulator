extends RefCounted
const Catalog=preload("res://scripts/io_devices/catalog.gd")
const Controls=preload("res://scripts/io_devices/controls.gd")
## Stateless expansion. io_device is a host descriptor, NEVER passed to MNA.
static func expand(model: Dictionary,id: String,n: Array,state: Dictionary,v: Dictionary={},runtime: Dictionary={}) -> Array:
	var kind := str(model.get("kind",""))
	if preload("res://scripts/commercial_devices/catalog.gd").supports(kind):return preload("res://scripts/commercial_devices/peripherals.gd").expand(model,id,n,state,v,runtime)
	if not Catalog.supports(kind) or n.size()!=int(Catalog.PIN_COUNTS[kind]):return []
	var c := Controls.defaults(kind)
	var initial: Dictionary=state.get("io_input",state)
	var input_now: Dictionary=runtime.get("__inputs",{}).get(id,{})
	for key in c:
		if initial.has(key):c[key]=initial[key]
		if input_now.has(key):c[key]=input_now[key]
	var s: Dictionary=runtime.get(id,{})
	var out: Array=[{"id":id,"kind":"io_device","model":kind,"nodes":n,"control":c}]
	match kind:
		"io_encoder":
			var gray: int=[0,1,3,2][posmod(int(s.get("phase",0)),4)]
			for bit in 2:resistor(out,id+"/contact"+str(bit),n[bit],n[2],.01 if gray&(1<<bit) else 1e12)
		"io_keypad":
			for key in 12:resistor(out,id+"/key"+str(key),n[key/3],n[4+key%3],.01 if int(c.get("keys",0))&(1<<key) else 1e12)
		"io_slider":track(out,id,n[0],n[1],n[2],float(c.get("x",.5)))
		"io_joystick":
			track(out,id+"/x",n[0],n[1],n[3],float(c.get("x",.5)))
			track(out,id+"/y",n[0],n[2],n[3],float(c.get("y",.5)))
			resistor(out,id+"/switch",n[4],n[5],.01 if c.get("pressed",false) else 1e12)
		"io_selector":
			for pin in 3:resistor(out,id+"/contact"+str(pin),n[0],n[pin+1],.01 if pin==int(c.get("position",0)) else 1e12)
		"io_rgb","io_bar","io_matrix":
			var count := 3 if kind=="io_rgb" else 4 if kind=="io_bar" else 16
			for index in count:
				out.append({"id":id+"/led"+str(index),"kind":"LED","a":n[index/4] if kind=="io_matrix" else n[index],"b":n[4+index%4] if kind=="io_matrix" else n[-1],"vf":[1.8,2.1,3.][index] if kind=="io_rgb" else 1.8,"ron":10.})
		"io_motor","io_vibration":
			resistor(out,id+"/winding",n[0],id+"/@armature",20.)
			out.append({"id":id+"/emf","kind":"V","a":id+"/@armature","b":n[1],"value":.02*float(s.get("omega",0)),"resistance":0.})
		"io_relay":
			resistor(out,id+"/coil",n[0],n[1],125.)
			resistor(out,id+"/nc",n[2],n[3],1e12 if s.get("closed",false) else .05)
			resistor(out,id+"/no",n[2],n[4],.05 if s.get("closed",false) else 1e12)
		"io_bridge":
			resistor(out,id+"/power",n[0],n[1],10000.)
			for index in 2:
				resistor(out,id+"/in"+str(index),n[2+index],n[1],1e6)
				var high := voltage(v,n[2+index],n[1])>=.7*voltage(v,n[0],n[1])
				resistor(out,id+"/out"+str(index),n[4+index],n[0] if high else n[1],2. if s.get("powered",false) else 1e12)
		"io_pixels","io_graphic","io_servo":
			var current := .002
			if kind=="io_pixels":
				for channel in s.get("pixels",[]):current+=float(channel)/255.*.02
			elif kind=="io_servo":current=.02+minf(.2,absf(float(s.get("target",90))-float(s.get("angle",90)))*.002)
			resistor(out,id+"/power",n[0],n[1],5./current)
			for index in range(2,n.size()):resistor(out,id+"/input"+str(index),n[index],n[1],1e7)
	return out

static func resistor(out: Array,id: String,a: String,b: String,value: float) -> void:
	out.append({"id":id,"kind":"R","a":a,"b":b,"value":value})
static func track(out: Array,id: String,a: String,w: String,b: String,x: float) -> void:
	resistor(out,id+"/upper",a,w,maxf(.01,10000.*(1.-clampf(x,0,1))))
	resistor(out,id+"/lower",w,b,maxf(.01,10000.*clampf(x,0,1)))
static func voltage(v: Dictionary,a: String,b: String) -> float:return float(v.get(a,0))-float(v.get(b,0))

## Tick once per authoritative fixed electrical step, using the last valid solve.
## State is JSON-safe. Invalid solve freezes state; no fabricated voltage readings.
static func tick(device: Dictionary,result: Dictionary,old: Dictionary,dt: float) -> Dictionary:
	if preload("res://scripts/commercial_devices/catalog.gd").supports(str(device.get("model",""))):return preload("res://scripts/commercial_devices/peripherals.gd").tick(device,result,old,dt)
	if not result.get("ok",false) or not is_finite(dt) or dt<0 or dt>.01:return old.duplicate(true)
	var s := old.duplicate(true)
	var kind := str(device.model);var n: Array=device.nodes;var id := str(device.id)
	var c: Dictionary=device.get("control",{})
	var v: Dictionary=result.get("v",{});var currents: Dictionary=result.get("i",{})
	s.control=c.duplicate(true)
	match kind:
		"io_encoder":
			var target := int(c.get("detent",0))*4
			var phase := int(s.get("phase",0))
			s.phase=phase+signi(target-phase)
		"io_rgb","io_bar","io_matrix":
			var count := 3 if kind=="io_rgb" else 4 if kind=="io_bar" else 16
			var levels: Array=[]
			for index in count:levels.append(clampf(float(currents.get(id+"/led"+str(index),0))/.02,0,1))
			s.levels=levels
		"io_motor","io_vibration":
			var torque := .02*float(currents.get(id+"/winding",0))
			var decay := exp(-2.*dt)
			s.omega=float(s.get("omega",0))*decay+torque/.00002*(1.-decay)
			s.angle=fposmod(float(s.get("angle",0))+float(s.omega)*dt,TAU)
			s.torque=torque;s.force=.0005*.002*float(s.omega)*float(s.omega) if kind=="io_vibration" else 0.
		"io_relay":
			var coil := absf(voltage(v,n[0],n[1]))
			s.closed=coil>=1.5 if s.get("closed",false) else coil>=3.5
		"io_pixels","io_graphic","io_servo","io_bridge":
			var supply := voltage(v,n[0],n[1])
			s.powered=supply>=(4.5 if kind=="io_servo" else 2. if kind=="io_bridge" else 3.) and supply<=(6. if kind in ["io_servo","io_bridge"] else 5.5)
			if not s.powered:return {"powered":false,"control":c.duplicate(true)}
			if kind in ["io_pixels","io_graphic"]:serial_tick(kind,n,v,s,supply)
			elif kind=="io_servo":servo_tick(n,v,s,supply,dt)
	return s

static func serial_tick(kind: String,n: Array,v: Dictionary,s: Dictionary,supply: float) -> void:
	var active := voltage(v,n[4],n[1])<supply*.3
	var clk := voltage(v,n[3],n[1])>=supply*.7
	var field := "pixels" if kind=="io_pixels" else "cells"
	var size := 24 if kind=="io_pixels" else 32
	if not s.has(field):
		var data: Array=[];data.resize(size);data.fill(0);s[field]=data
	if not active:s.bits=0;s.byte=0;s.address=-1;s.pending=[]
	elif clk and not s.get("clk",false):
		s.byte=(int(s.get("byte",0))<<1)|(1 if voltage(v,n[2],n[1])>=supply*.7 else 0)
		s.bits=int(s.get("bits",0))+1
		if s.bits==8:
			var byte := int(s.byte)&255
			if int(s.get("address",-1))<0:s.address=byte%(8 if kind=="io_pixels" else 32);s.pending=[]
			elif kind=="io_graphic":s.cells[int(s.address)]=byte;s.address=(int(s.address)+1)%32
			else:
				var pending: Array=s.get("pending",[]);pending.append(byte);s.pending=pending
				if pending.size()==3:
					for channel in 3:s.pixels[int(s.address)*3+channel]=pending[channel]
					s.address=(int(s.address)+1)%8;s.pending=[]
			s.bits=0;s.byte=0
	s.clk=clk

static func servo_tick(n: Array,v: Dictionary,s: Dictionary,supply: float,dt: float) -> void:
	var high := voltage(v,n[2],n[1])>=supply*.7
	var time := float(s.get("time",0))+dt;s.time=time
	if high and not s.get("high",false):
		s.period=time-float(s.get("rise",time));s.rise=time
	if not high and s.get("high",false):
		var width := time-float(s.get("rise",time))
		if width>=.00099 and width<=.00201 and float(s.get("period",0))>=.01 and float(s.get("period",0))<=.03:
			s.target=clampf((width-.001)/.001,0,1)*180.;s.last_pulse=time
	s.high=high
	s.signal_valid=time-float(s.get("last_pulse",-1))<.06
	if s.signal_valid:s.angle=move_toward(float(s.get("angle",90)),float(s.get("target",90)),360.*dt)
	else:s.target=float(s.get("angle",90))
