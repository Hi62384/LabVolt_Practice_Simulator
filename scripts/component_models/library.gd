extends RefCounted
## Deterministic host-step models. No scene, network, audio or profile access.
const Serial = preload("res://scripts/component_models/serial_devices.gd")
const OFF := 1e12

static func resistor(id: String, a: String, b: String, value: float) -> Dictionary:
	return {"id":id,"kind":"R","a":a,"b":b,"value":maxf(.001,value)}

static func diode(id: String, a: String, b: String, vf := .7, ron := 1.) -> Dictionary:
	return {"id":id,"kind":"D","a":a,"b":b,"vf":vf,"ron":ron}

static func voltage(v: Dictionary, pin: String, ground: String) -> float:
	return float(v.get(pin,0))-float(v.get(ground,0))

static func level(v: float, supply: float) -> int:
	if v <= .3*supply:return 0
	if v >= .7*supply:return 1
	return -1

static func expand(model: Dictionary,id: String,n: Array,_state: Dictionary={},v: Dictionary={},runtime: Dictionary={}) -> Array:
	if n.size()!=model.pins.size():return []
	var s: Dictionary=runtime.get(id,{})
	var kind: String=model.worker_model
	var out: Array=[{"id":id,"kind":"stateful","model":"worker:"+kind,"nodes":n,"config":model}]
	match kind:
		"diode":out.append(diode(id+"/d",n[0],n[1],model.vf,model.ron))
		"zener":
			out.append(diode(id+"/forward",n[0],n[1],.7,1.))
			out.append(diode(id+"/avalanche",n[1],n[0],model.vz,model.ron))
		"tvs":
			# Anti-series Zener pair: threshold is vz + forward drop.
			out.append(diode(id+"/a",n[0],id+"/junction",model.vz,model.ron))
			out.append(diode(id+"/b",n[1],id+"/junction",model.vz,model.ron))
			out.append(diode(id+"/ar",id+"/junction",n[0],.7,1.))
			out.append(diode(id+"/br",id+"/junction",n[1],.7,1.))
		"bridge":
			for pin in 2:
				out.append(diode(id+"/positive"+str(pin),n[pin],n[2],model.vf,model.ron))
				out.append(diode(id+"/negative"+str(pin),n[3],n[pin],model.vf,model.ron))
		"mosfet","jfet":
			var sign_p := -1. if model.polarity=="P" else 1.
			var gate := sign_p*voltage(v,n[1],n[2])
			var drain := maxf(.000001,absf(voltage(v,n[0],n[2])))
			var conductance := 0.
			# Secant of a square-law channel at the preceding solved bias.
			# This is a host-step companion resistance, not an intra-MNA FET stamp.
			var overdrive := maxf(0.,gate-float(model.vth)) if kind=="mosfet" else clampf(gate-float(model.pinch),0.,absf(float(model.pinch)))
			var beta := 1./float(model.ron) if kind=="mosfet" else 1./(float(model.ron)*absf(float(model.pinch)))
			var channel_current := beta*(overdrive*drain-.5*drain*drain) if drain<overdrive else .5*beta*overdrive*overdrive
			conductance=maxf(0.,channel_current/drain)
			out.append(resistor(id+"/channel",n[0],n[2],1./maxf(1e-12,conductance)))
			out.append(resistor(id+"/gate",n[1],n[2],OFF))
			if kind=="mosfet":out.append(diode(id+"/body",n[0] if sign_p<0 else n[2],n[2] if sign_p<0 else n[0]))
			else:
				out.append(diode(id+"/gs",n[2] if sign_p<0 else n[1],n[1] if sign_p<0 else n[2]))
				out.append(diode(id+"/gd",n[0] if sign_p<0 else n[1],n[1] if sign_p<0 else n[0]))
		"fuse":out.append(resistor(id+"/link",n[0],n[1],OFF if s.get("blown",false) else float(model.ron)))
		"relay":
			out.append(resistor(id+"/coil",n[0],id+"/coil_node",model.resistance))
			out.append({"id":id+"/inductance","kind":"L","a":id+"/coil_node","b":n[1],"value":float(model.get("coil_inductance",.2))})
			out.append(resistor(id+"/nc",n[2],n[3],OFF if s.get("closed",false) else .05))
			out.append(resistor(id+"/no",n[2],n[4],.05 if s.get("closed",false) else OFF))
		"regulator":
			var input := voltage(v,n[0],n[1])
			var demand := clampf(float(s.get("load",0)),0.,float(model.limit))
			var target := minf(float(model.target),maxf(0.,input-float(model.dropout)))
			if input>0.:
				out.append({"id":id+"/output","kind":"supply","a":n[2],"b":n[1],"value":target,"resistance":.1,"limit":model.limit})
				out.append({"id":id+"/input","kind":"I","a":n[0],"b":n[1],"value":demand+float(model.iq)})
			else:out.append(resistor(id+"/output_off",n[2],n[1],OFF))
			out.append(resistor(id+"/input_leak",n[0],n[1],1e8))
		"uln2003":
			for pin in 7:
				out.append(resistor(id+"/input"+str(pin),n[pin],n[7],2700.))
				out.append(resistor(id+"/sink"+str(pin),n[15-pin],n[7],2. if voltage(v,n[pin],n[7])>1.4 else OFF))
				out.append(diode(id+"/clamp"+str(pin),n[15-pin],n[8]))
		_:
			var g: String=n[int(model.ground)];var supply: String=n[int(model.supply)]
			var powered: bool=s.get("powered",false)
			out.append(resistor(id+"/power",supply,g,50000.))
			var driven: Dictionary=s.get("drive",{}) if powered else {}
			for pin in n.size():
				if pin in [int(model.ground),int(model.supply)]:continue
				var drive: int=int(driven.get(str(pin),-1))
				out.append(resistor(id+"/pin"+str(pin),n[pin],supply if drive==1 else g,float(model.get("driver",40.)) if drive>=0 else 1e9))
			if kind=="switch4066":
				for pair in [[0,1,12],[3,2,4],[7,8,5],[10,9,11]]:
					out.append(resistor(id+"/switch"+str(pair[0]),n[pair[0]],n[pair[1]],float(model.ron) if powered and level(voltage(v,n[pair[2]],g),voltage(v,supply,g))==1 else OFF))
			if kind=="mux4051":
				var selected: int=s.get("selected",-1)
				for pin in 8:out.append(resistor(id+"/mux"+str(pin),n[2],n[[12,13,14,11,0,4,1,3][pin]],float(model.ron) if powered and selected==pin else OFF))
			if kind=="dac4921":
				var target := float(s.get("code",0))/4096.*voltage(v,n[5],g)*float(s.get("gain",1))
				if powered and s.get("active",false):
					out.append({"id":id+"/analog","kind":"V","a":n[7],"b":g,"value":clampf(target,0.,maxf(0.,voltage(v,supply,g))),"resistance":50.})
					out.append({"id":id+"/output_load","kind":"I","a":supply,"b":g,"value":maxf(0.,float(s.get("load",0)))})
			if kind=="pcf8574":
				for pin in [3,4,5,6,8,9,10,11]:
					if powered and int(s.get("latch",255))&(1<<[3,4,5,6,8,9,10,11].find(pin)):
						out.append(resistor(id+"/pullup"+str(pin),n[pin],supply,50000.))
			if kind=="l293d":
				for pin in [4,11,12]:out.append(resistor(id+"/ground"+str(pin),n[pin],g,.01))
				for pair in [[0,1,2],[0,6,5],[8,9,10],[8,14,13]]:
					var enabled := powered and level(voltage(v,n[pair[0]],g),voltage(v,supply,g))==1
					var high := level(voltage(v,n[pair[1]],g),voltage(v,supply,g))
					out.append(resistor(id+"/motor"+str(pair[2]),n[pair[2]],n[7] if high==1 else g,3. if enabled and high>=0 else OFF))
					out.append(diode(id+"/hi"+str(pair[2]),n[pair[2]],n[7]))
					out.append(diode(id+"/lo"+str(pair[2]),g,n[pair[2]]))
			if kind=="rs485":
				out.append(resistor(id+"/receiver_a",n[5],g,12000.))
				out.append(resistor(id+"/receiver_b",n[6],g,12000.))
				var enabled := powered and level(voltage(v,n[2],g),voltage(v,supply,g))==1
				var bit := level(voltage(v,n[3],g),voltage(v,supply,g))
				for pin in [5,6]:out.append(resistor(id+"/bus"+str(pin),n[pin],supply if (bit==1)==(pin==5) else g,25. if enabled and bit>=0 else OFF))
	return out

static func tick(model: Dictionary,n: Array,v: Dictionary,old: Dictionary,dt: float,currents: Dictionary={},id: String="") -> Dictionary:
	var s := old.duplicate(true)
	var kind: String=model.worker_model
	if n.size()!=model.pins.size() or not is_finite(dt) or dt<0.:return s
	match kind:
		"fuse":
			var current := absf(float(currents.get(id+"/link",0)))
			# Rated current is thermally balanced; excess I² accumulates adiabatically.
			s.heat=maxf(0.,float(s.get("heat",0))+(current*current-float(model.current)*float(model.current))*dt)
			s.blown=bool(s.get("blown",false)) or float(s.heat)>=float(model.i2t)
			return s
		"relay":
			var current := absf(float(currents[id+"/coil"])) if currents.has(id+"/coil") else absf(voltage(v,n[0],n[1]))/float(model.resistance)
			var desired := current>=float(model.release) if s.get("closed",false) else current>=float(model.pickup)
			if desired!=bool(s.get("pending",false)):s.elapsed=0.
			s.pending=desired;s.elapsed=float(s.get("elapsed",0))+dt
			if s.elapsed>=float(model.delay):s.closed=desired
			return s
		"regulator":s.load=maxf(0.,-float(currents.get(id+"/output",0)));return s
	if not model.has("supply"):return s
	var g: String=n[int(model.ground)]
	var supply := voltage(v,n[int(model.supply)],g)
	var powered := supply>=float(model.vmin) and supply<=float(model.vmax)
	s.powered=powered;s.drive={}
	if not powered:
		# EEPROM array persists, volatile protocol/control state does not.
		return {"powered":false,"memory":s.get("memory",{}),"status":s.get("status",0),"busy":maxf(0.,float(s.get("busy",0))-dt)} if kind=="eeprom25" else {"powered":false}
	var p: Array=[]
	for pin in n:p.append(level(voltage(v,pin,g),supply))
	match kind:
		"nor":
			for gate in [[1,2,0],[4,5,3],[7,8,9],[10,11,12]]:
				if p[gate[0]]>=0 and p[gate[1]]>=0:s.drive[str(gate[2])]=1 if p[gate[0]]==0 and p[gate[1]]==0 else 0
		"schmitt":
			for gate in [[0,1],[2,3],[4,5],[8,7],[10,9],[12,11]]:
				var key := "schmitt"+str(gate[0]);var value := voltage(v,n[gate[0]],g)
				if value>=.65*supply:s[key]=0
				elif value<=.35*supply:s[key]=1
				if s.has(key):s.drive[str(gate[1])]=s[key]
		"shift165":
			var clock: bool=p[1]==1 or p[14]==1
			if p[0]==0:
				var word := 0
				for bit in 8:
					if p[[10,11,12,13,2,3,4,5][bit]]==1:word|=1<<bit
				s.word=word
			elif p[0]==1 and clock and not s.get("clock",true) and p[9]>=0:s.word=((int(s.get("word",0))<<1)|int(p[9]))&255
			s.clock=clock;s.drive={"8":1 if int(s.get("word",0))&128 else 0,"6":0 if int(s.get("word",0))&128 else 1}
		"counter4017":
			var clock: bool=p[13]==1 and p[12]==0
			if p[14]==1:s.count=0
			elif p[14]==0 and clock and not s.get("clock",true):s.count=(int(s.get("count",0))+1)%10
			s.clock=clock
			var order: Array=[2,1,3,6,9,0,4,5,8,10]
			for bit in 10:s.drive[str(order[bit])]=1 if bit==int(s.get("count",0)) else 0
			s.drive["11"]=1 if int(s.get("count",0))<5 else 0
		"mux4051":
			s.selected=-1
			if p[5]==0 and p[8]>=0 and p[9]>=0 and p[10]>=0:s.selected=int(p[10])+2*int(p[9])+4*int(p[8])
		"comparator":
			for gate in [[2,1,0],[4,5,6]]:
				var a := voltage(v,n[gate[0]],g);var b := voltage(v,n[gate[1]],g)
				if minf(a,b)>=0. and maxf(a,b)<=supply-1.5 and a<b:s.drive[str(gate[2])]=0
		"rs485":
			if p[1]==0:
				var diff := voltage(v,n[5],n[6])
				if absf(diff)>=.2:s.receiver=1 if diff>0 else 0
				if s.has("receiver"):s.drive["0"]=s.receiver
		"adc3008","dac4921","eeprom25":
			s=Serial.tick(model,n,v,p,s,dt)
			if kind=="dac4921":s.load=maxf(0.,-float(currents.get(id+"/analog",0)))
		"pcf8574":s=preload("res://scripts/component_models/i2c_expander.gd").tick(n,v,p,s,supply)
	return s

