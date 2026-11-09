extends SceneTree
const Catalog = preload("res://scripts/component_models/catalog.gd")
const Lib = preload("res://scripts/component_models/library.gd")
const Solver = preload("res://scripts/electronics_solver.gd")
var catalog := Catalog.all()
var checks := 0
var failures := 0

func check(condition: bool,label: String) -> void:
	checks+=1
	if not condition:failures+=1;push_error(label)

func near(actual: float,expected: float,tolerance: float,label: String) -> void:
	check(absf(actual-expected)<=tolerance,label+": "+str(actual)+" expected "+str(expected))

func chip(key: String) -> Dictionary:
	var m: Dictionary=catalog[key];var n: Array=[];var v := {}
	for pin in m.pins.size():n.append(str(pin));v[str(pin)]=0.
	if m.has("supply"):v[n[int(m.supply)]]=5.
	return {"m":m,"n":n,"v":v,"s":{}}

func tick(c: Dictionary,dt := .0005,currents: Dictionary={}) -> void:
	c.s=Lib.tick(c.m,c.n,c.v,c.s,dt,currents,"test")

func setpin(c: Dictionary,pin: int,value: float) -> void:
	c.v[str(pin)]=value;tick(c)

func parts(c: Dictionary) -> Array:
	return Lib.expand(c.m,"test",c.n,{},c.v,{"test":c.s}).filter(func(p):return p.kind!="stateful")

func source(id: String,a: String,b: String,value: float) -> Dictionary:
	return {"id":id,"kind":"V","a":a,"b":b,"value":value,"resistance":.01}

func solve(p: Array) -> Dictionary:
	var result: Dictionary=Solver.new().solve(p,[],.0005)
	check(result.get("ok",false),"MNA solve: "+str(result.get("error","")))
	return result

func _initialize() -> void:
	check(JSON.parse_string(JSON.stringify(catalog))==JSON.parse_string(FileAccess.get_file_as_string("res://assets/workers/models/catalog.json")),"Exportable catalog equals canonical JSON")
	var baseline := preload("res://scripts/electronics_catalog.gd").all()
	check(catalog.keys().all(func(key):return baseline.has(key) and baseline[key]==catalog[key]),"Integrated catalog retains every fragment definition without overriding it")
	for key in catalog:
		var c := chip(key);tick(c)
		check(c.m.category in ["Basic","IC","PCB","Input","Output"],key+" category")
		check(c.m.footprint.pitch_mm>0,key+" footprint")
		var p := parts(c)
		check(not p.is_empty() and p.size()<=96,key+" bounded primitive expansion")
		var ids := {}
		for primitive in p:
			check(primitive.kind in ["R","D","V","I","L","supply"],key+" primitive contract")
			check(not ids.has(primitive.id),key+" unique primitive IDs");ids[primitive.id]=true
		var decoded = JSON.parse_string(JSON.stringify(c.s))
		check(decoded is Dictionary,key+" JSON state")
	analog_tests();logic_tests();serial_tests();i2c_tests();adapter_tests();edge_tests()
	print("MODELS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func analog_tests() -> void:
	for key in ["schottky","rectifier","zener5v1"]:
		var c := chip(key)
		var p := parts(c);p.append_array([source("s","v","1",5.),Lib.resistor("r","v","0",1000.)])
		var r := solve(p)
		near(absf(r.i.r),(5.-float(c.m.get("vf",.7)))/(1000.01+(1. if key=="zener5v1" else float(c.m.get("ron",1.)))),1e-5,key+" forward current")
		p=parts(c);p.append_array([source("s","1","v",12.),Lib.resistor("r","v","0",1000.)]);r=solve(p)
		if key=="zener5v1":near(absf(r.i.r),(12.-5.1)/1005.01,1e-5,"Zener reverse clamp")
		else:check(absf(r.i.r)<1e-7,key+" reverse blocking")
	for polarity in [1.,-1.]:
		var c := chip("nmos" if polarity>0 else "pmos")
		c.v={"0":5.*polarity,"1":0.,"2":0.}
		var p := parts(c);p.append_array([source("s","v","2",5.*polarity),Lib.resistor("r","v","0",100.)])
		var r := solve(p);check(absf(r.i.r)<1e-7,"MOS cutoff")
		c.v["1"]=5.*polarity;p=parts(c);p.append_array([source("s","v","2",5.*polarity),Lib.resistor("r","v","0",100.)]);r=solve(p)
		near(absf(r.i.r),5./100.2322222,1e-5,"MOS loaded on channel")
	for polarity in [1.,-1.]:
		var c := chip("njfet" if polarity>0 else "pjfet")
		c.v={"0":.1*polarity,"1":0.,"2":0.}
		var p := parts(c);p.append(source("s","0","2",.1*polarity));var r := solve(p)
		near(absf(r.i["test/channel"]),.0009875,1e-6,"JFET zero bias conduction")
		c.v["1"]=-4.*polarity;p=parts(c);p.append(source("s","0","2",.1*polarity));r=solve(p)
		check(absf(r.i["test/channel"])<1e-9,"JFET pinch off")
	for sign_v in [1.,-1.]:
		var c := chip("bridge");var p := parts(c)
		p.append_array([source("ac","0","1",10.*sign_v),Lib.resistor("load","2","3",1000.)]);var r := solve(p)
		near(r.i.load,(10.-1.4)/1002.01,1e-5,"Bridge both polarities positive load current")
		c=chip("tvs12");p=parts(c);p.append_array([source("s","v","1",20.*sign_v),Lib.resistor("r","v","0",100.)]);r=solve(p)
		near(absf(r.i.r),(20.-12.7)/102.01,1e-5,"TVS both polarities")
	var c := chip("fuse0_1")
	for i in 100:tick(c,.001,{"test/link":.1})
	check(not c.s.blown,"Fuse holds rated current")
	for i in 4:tick(c,.001,{"test/link":1.})
	check(c.s.blown,"Fuse I2t overload trips")
	tick(c,.1,{"test/link":0.});check(c.s.blown,"Fuse stays blown")
	check(parts(c)[0].value>=1e12,"Blown fuse opens circuit")
	c=chip("relay5");c.v["0"]=5.
	tick(c,.005);check(not c.s.get("closed",false),"Relay pickup mechanical delay")
	tick(c,.006);check(c.s.closed,"Relay pickup")
	c.v["0"]=2.;tick(c,.02);check(c.s.closed,"Relay hysteresis")
	c.v["0"]=0.;tick(c,.02);check(not c.s.closed,"Relay release")
	for key in ["reg3_3","reg5_0","reg12_0"]:
		c=chip(key);c.v["0"]=20.;c.v["1"]=0.
		var p := parts(c);p.append_array([source("s","0","1",20.),Lib.resistor("load","2","1",100.)]);var r := solve(p)
		near(r.i.load,float(c.m.target)/100.1,1e-5,key+" loaded regulation")
		tick(c,.0005,r.i);near(c.s.load,float(c.m.target)/100.1,1e-5,key+" input load tracks output current")
		c.v["0"]=3.;p=parts(c);p.append_array([source("s","0","1",3.),Lib.resistor("load","2","1",100.)]);r=solve(p)
		near(r.i.load,1./100.1,1e-5,key+" dropout")
		c.v["0"]=20.;p=parts(c);p.append_array([source("s","0","1",20.),Lib.resistor("load","2","1",.1)]);r=solve(p)
		near(r.i.load,.5,1e-5,key+" short current limit")

func logic_tests() -> void:
	var c := chip("hc02");tick(c);check(c.s.drive["0"]==1,"NOR low inputs")
	setpin(c,1,5.);check(c.s.drive["0"]==0,"NOR high input")
	setpin(c,1,2.5);check(not c.s.drive.has("0"),"Undefined logic high impedance")
	setpin(c,13,9.);check(not c.s.powered,"Overvoltage power rejection")
	c=chip("hc14");tick(c);check(c.s.drive["1"]==1,"Schmitt initial low")
	setpin(c,0,2.5);check(c.s.drive["1"]==1,"Schmitt retains within band")
	setpin(c,0,4.);setpin(c,0,2.5);check(c.s.drive["1"]==0,"Schmitt high hysteresis")
	c=chip("hc165");c.v["5"]=5.;tick(c);check(c.s.drive["8"]==1,"165 async parallel load")
	setpin(c,0,5.);setpin(c,1,0.);setpin(c,1,5.);check(c.s.drive["8"]==0,"165 shift rising edge")
	var word: int=c.s.word;setpin(c,14,5.);setpin(c,1,0.);setpin(c,1,5.);check(c.s.word==word,"165 clock inhibit")
	c=chip("cd4017");setpin(c,14,5.);check(c.s.count==0,"4017 async reset")
	setpin(c,14,0.)
	for i in 12:setpin(c,13,0.);setpin(c,13,5.)
	check(c.s.count==2 and c.s.drive["3"]==1,"4017 modulo10 decoded count")
	setpin(c,12,5.);setpin(c,13,0.);setpin(c,13,5.);check(c.s.count==2,"4017 inhibit")
	c=chip("cd4066");tick(c);var p := parts(c);check(p[-4].value==1e12,"4066 off")
	setpin(c,12,5.);p=parts(c);p.append_array([source("s","0","6",2.),Lib.resistor("load","1","6",1000.)]);var r := solve(p)
	near(r.i.load,2./1470.01,1e-5,"4066 bilateral loading")
	c=chip("cd4051");tick(c);check(c.s.selected==0,"4051 channel zero")
	setpin(c,10,5.);setpin(c,8,5.);check(c.s.selected==5,"4051 binary channel select")
	setpin(c,5,5.);check(c.s.selected==-1,"4051 inhibit")
	c=chip("lm393");setpin(c,1,2.);setpin(c,2,1.);check(c.s.drive["0"]==0,"Comparator sink")
	setpin(c,2,3.);check(not c.s.drive.has("0"),"Comparator open collector high")
	c=chip("rs485");setpin(c,5,3.);setpin(c,6,2.);check(c.s.drive["0"]==1,"485 differential receive")
	setpin(c,5,1.);check(c.s.drive["0"]==0,"485 reversed receive")
	setpin(c,1,5.);check(not c.s.drive.has("0"),"485 receiver disabled")
	c=chip("uln2003");setpin(c,0,5.);p=parts(c);p.append_array([source("s","v","7",5.),Lib.resistor("load","v","15",100.)]);r=solve(p)
	near(r.i.load,5./102.01,1e-5,"ULN sink actual load current")
	c=chip("l293d");setpin(c,0,5.);setpin(c,1,5.);setpin(c,6,0.);p=parts(c)
	p.append_array([source("logic","15","3",5.),source("motor","7","3",12.),Lib.resistor("load","2","5",100.)]);r=solve(p)
	near(r.i.load,12./106.01,.001,"L293 H bridge load and motor supply")

func spi(c: Dictionary,bytes: Array,cs: int,clk: int,di: int,dout: int) -> Array:
	setpin(c,cs,5.);setpin(c,clk,0.);setpin(c,cs,0.)
	var received: Array=[]
	for byte in bytes:
		var word := 0
		for bit in range(7,-1,-1):
			setpin(c,di,5. if int(byte)&(1<<bit) else 0.)
			word=(word<<1)|int(c.s.get("drive",{}).get(str(dout),0))
			setpin(c,clk,5.);setpin(c,clk,0.)
		received.append(word&255)
	setpin(c,cs,5.)
	return received

func serial_tests() -> void:
	var c := chip("mcp4921");setpin(c,5,4.096)
	spi(c,[0x38,0x00],1,2,3,-1);tick(c)
	check(c.s.code==2048 and c.s.active,"DAC SPI command, LDAC low")
	var p := parts(c);p.append_array([source("power","0","6",5.),Lib.resistor("load","7","6",1000.)]);var r := solve(p)
	near(r.i.load,2.048/1050.,1e-5,"DAC output impedance loading")
	setpin(c,4,5.);spi(c,[0x30,0x00],1,2,3,-1);check(c.s.code==2048,"DAC LDAC hold")
	setpin(c,4,0.);check(c.s.code==0,"DAC LDAC commit")
	c=chip("mcp3008");setpin(c,14,5.);setpin(c,0,2.5)
	var rx := spi(c,[1,128,0],9,12,10,11)
	check(((int(rx[1])&3)<<8|int(rx[2]))==512,"ADC standard 3-byte SPI half scale: "+str(rx))
	check(not c.s.drive.has("11"),"ADC deselect tri-state")
	c=chip("eeprom25");setpin(c,6,5.);setpin(c,2,5.)
	spi(c,[2,0,0,0xA5],0,5,4,1);check(c.s.get("memory",{}).is_empty(),"EEPROM write requires WREN")
	spi(c,[6],0,5,4,1);check(c.s.wel,"EEPROM WREN")
	spi(c,[2,0,63,0xA5,0x5A],0,5,4,1)
	check(c.s.memory.get("63")==0xA5 and c.s.memory.get("0")==0x5A,"EEPROM 64-byte page wraps")
	check(not c.s.wel and c.s.busy>0.,"EEPROM busy and WEL clears")
	tick(c,.006);rx=spi(c,[3,0,63,0,0],0,5,4,1)
	check(rx[3]==0xA5 and rx[4]==255,"EEPROM sequential read across page: "+str(rx))
	setpin(c,7,0.);setpin(c,7,5.);check(c.s.memory.get("63")==0xA5,"EEPROM retains across power cycle")
	var saved = JSON.parse_string(JSON.stringify(c.s));c.s=saved;tick(c)
	check(c.s.memory.get("0")==0x5A,"EEPROM JSON reload")

func i2c_level(c: Dictionary,scl: bool,sda: bool) -> void:
	c.v["13"]=5. if scl else 0.
	c.v["14"]=0. if c.s.get("sda_low",false) or not sda else 5.
	tick(c)

func i2c_byte(c: Dictionary,byte: int) -> bool:
	for bit in range(7,-1,-1):
		var high := (byte&(1<<bit))!=0
		i2c_level(c,false,high);i2c_level(c,true,high)
	i2c_level(c,false,true)
	var ack: bool=c.s.get("sda_low",false)
	i2c_level(c,true,true);i2c_level(c,false,true)
	return ack

func i2c_tests() -> void:
	var c := chip("pcf8574");i2c_level(c,true,true);i2c_level(c,true,false)
	check(i2c_byte(c,0x40),"PCF address ACK")
	check(i2c_byte(c,0xA5),"PCF write ACK")
	check(c.s.latch==0xA5,"PCF output latch")
	i2c_level(c,false,false);i2c_level(c,true,false);i2c_level(c,true,true)
	check(c.s.drive.get("4",-1)==0 and not c.s.drive.has("3"),"PCF open drain port outputs")
	i2c_level(c,true,false);check(not i2c_byte(c,0x42),"PCF wrong address NACK")

func adapter_tests() -> void:
	var host = preload("res://scripts/component_models/standalone.gd").new()
	var c := chip("nmos")
	var devices: Array=[{"id":"q","model":c.m,"nodes":["d","g","s"]}]
	var external: Array=[source("power","v","s",5.),source("gate","g","s",5.),Lib.resistor("load","v","d",100.)]
	var r: Dictionary
	for i in 5:r=host.step(devices,external,[],.0005)
	check(r.ok,"Standalone host solves")
	near(r.i.load,5./100.0766,1e-4,"Standalone uses solved gate voltage")
	var saved: Dictionary=host.snapshot();host.restore(JSON.parse_string(JSON.stringify(saved)))
	check(host.snapshot().has("q"),"Standalone JSON restore")
	check(not host.step(devices,external,[],0.).ok,"Standalone invalid dt")

func edge_tests() -> void:
	# Independent square-law reference at fixed high drain bias, not a truth-table stub.
	for key in ["nmos","pmos","njfet","pjfet"]:
		var c := chip(key);var polarity := -1. if key.begins_with("p") else 1.
		c.v={"0":10.*polarity,"1":3.*polarity if "mos" in key else -2.*polarity,"2":0.}
		var p := parts(c);p.append(source("s","0","2",10.*polarity));var r := solve(p)
		near(absf(r.i["test/channel"]),10./4.01 if "mos" in key else 10./2000.01,1e-5,key+" square-law saturation")
	var relay := chip("relay5");var solver := Solver.new();var p := parts(relay)
	p.append_array([source("s","0","1",5.),Lib.diode("flyback","1","0")])
	var r: Dictionary
	for i in 30:r=solver.solve(p,[],.0005)
	near(r.i["test/inductance"],5./125.01*(1.-pow(400./525.01,30)),1e-6,"Relay coil steady current")
	p=parts(relay);p.append(Lib.diode("flyback","1","0"));r=solver.solve(p,[],.0005)
	check(r.ok and r.i["test/inductance"]>.02 and r.i.flyback>0.,"Relay inductive flyback uses stored coil current")
	check(absf(r.drop.flyback)<.8,"External flyback diode bounds coil reversal")
	var c := chip("mcp3008");setpin(c,14,5.)
	for channel in 8:
		setpin(c,channel,float(channel)/8.*5.)
		var rx := spi(c,[1,128|(channel<<4),0],9,12,10,11)
		check(((int(rx[1])&3)<<8|int(rx[2]))==channel*128,"ADC wired channel "+str(channel))
	setpin(c,0,6.);var rx := spi(c,[1,128,0],9,12,10,11)
	check(((int(rx[1])&3)<<8|int(rx[2]))==1023,"ADC upper quantization clamp")
	setpin(c,0,3.);setpin(c,1,1.);rx=spi(c,[1,0,0],9,12,10,11)
	check(((int(rx[1])&3)<<8|int(rx[2]))==409,"ADC pseudo-differential positive")
	rx=spi(c,[1,16,0],9,12,10,11)
	check(((int(rx[1])&3)<<8|int(rx[2]))==0,"ADC pseudo-differential negative clamps")
	c=chip("eeprom25");setpin(c,6,5.);setpin(c,2,5.)
	spi(c,[6],0,5,4,1);spi(c,[1,0x8C],0,5,4,1);tick(c,.006)
	spi(c,[6],0,5,4,1);spi(c,[2,0,0,0x77],0,5,4,1);tick(c,.006)
	check(c.s.get("memory",{}).is_empty(),"EEPROM block protection prevents array write")
	setpin(c,2,0.);spi(c,[6],0,5,4,1);spi(c,[1,0],0,5,4,1);tick(c,.006)
	check(c.s.status==0x8C,"EEPROM WP with WPEN locks status")
	setpin(c,7,0.);setpin(c,7,5.);check(c.s.status==0x8C,"EEPROM protection status is nonvolatile")
	setpin(c,0,0.);setpin(c,6,0.)
	var bits: int=c.s.bits
	setpin(c,5,5.);setpin(c,5,0.);check(c.s.bits==bits and not c.s.drive.has("1"),"EEPROM HOLD pauses and releases SO")
	c=chip("pcf8574");c.s.latch=255
	for pin in [3,4,5,6,8,9,10,11]:c.v[str(pin)]=5.
	c.v["4"]=0.;c.v["9"]=0.
	i2c_level(c,true,true);i2c_level(c,true,false);check(i2c_byte(c,0x41),"PCF read address ACK")
	var byte := 0
	for bit in 8:
		byte=(byte<<1)|(0 if c.s.get("sda_low",false) else 1)
		i2c_level(c,true,true);i2c_level(c,false,true)
	check(byte==0xDD,"PCF port reads actual external pins: "+str(byte))
	i2c_level(c,true,true);i2c_level(c,false,true)
	check(c.s.phase=="idle","PCF master NACK terminates read")
	# Verify a released port is a weak electrical pullup, and a zero is a real sink.
	c=chip("pcf8574");tick(c);p=parts(c);p.append_array([source("s","15","7",5.),Lib.resistor("load","3","7",10000.)]);r=solve(p)
	near(r.drop.load,5./6.,.001,"PCF released port weak pullup loading")
	c.s.latch=254;tick(c);p=parts(c);p.append_array([source("s","15","7",5.),Lib.resistor("load","15","3",1000.)]);r=solve(p)
	near(r.i.load,5./1040.01,1e-5,"PCF low output sinks external load")
	c=chip("rs485");setpin(c,2,5.);setpin(c,3,5.);p=parts(c)
	p.append_array([source("s","7","4",5.),Lib.resistor("termination","5","6",120.)]);r=solve(p)
	near(r.drop.termination,5.*120./170.,.01,"RS485 finite driver under 120 ohm termination and receiver loading")



