extends RefCounted
const Catalog=preload("res://scripts/commercial_devices/catalog.gd")
const LCD=preload("res://scripts/commercial_devices/hd44780.gd")
const Registers=preload("res://scripts/commercial_devices/registers.gd")
const I2C=preload("res://scripts/commercial_devices/i2c_slave.gd")

static func r(out: Array,id: String,a: String,b: String,value: float) -> void:out.append({"id":id,"kind":"R","a":a,"b":b,"value":value})
static func expand(model: Dictionary,id: String,n: Array,state: Dictionary,v: Dictionary,runtime: Dictionary) -> Array:
	var kind:=str(model.kind)
	if n.size()!=Catalog.pins(kind).size():return []
	n=Catalog.logical_nodes(kind,n)
	if kind=="quartz":
		return [{"id":id+"/rm","kind":"R","a":n[0],"b":id+"/a","value":35000.},{"id":id+"/lm","kind":"L","a":id+"/a","b":id+"/b","value":8.},{"id":id+"/cm","kind":"C","a":id+"/b","b":n[1],"value":1.0/(pow(TAU*32768.,2)*8.)},{"id":id+"/c0","kind":"C","a":n[0],"b":n[1],"value":1.2e-12}]
	if kind in ["lm358","lm324"]:return opamp(kind,id,n,v)
	var controls: Dictionary=runtime.get("__inputs",{}).get(id,state.get("io_input",{}))
	var out: Array=[{"id":id,"kind":"io_device","model":kind,"nodes":n,"logical_pins":true,"control":controls,"columns":int(model.get("columns",16)),"rows":int(model.get("rows",2))}]
	var s: Dictionary=runtime.get(id,{})
	var ground: String=n[0] if kind=="hd44780" else n[1]
	var power: String=n[1] if kind=="hd44780" else n[0]
	var draw:=0.002
	if kind=="ws2812":
		draw=0.008
		for value in s.get("pixels",[]):draw+=float(value)/255.0*0.02
	r(out,id+"/power",power,ground,5./draw)
	for index in n.size():
		if n[index] not in [ground,power]:r(out,id+"/in"+str(index),n[index],ground,1e9)
	if kind=="hd44780":out.append({"id":id+"/backlight","kind":"LED","a":n[14],"b":n[15],"vf":3.0,"ron":10.0})
	if kind=="hd44780" and int(s.get("read_drive",-1))>=0:
		for bit in 8:
			if s.get("four",false) and bit<4:continue
			r(out,id+"/read"+str(bit),n[6+bit],power if int(s.read_drive)&(1<<bit) else ground,80.)
	elif kind in ["ssd1306","pca9685"]:
		if s.get("bus",{}).get("low",false):r(out,id+"/sda",n[3],ground,25.)
		if kind=="pca9685" and s.get("powered",false):
			var regs: Array=s.registers;var oe:=voltage(v,n[4],ground)>=0.7*voltage(v,power,ground)
			for channel in 16:
				var level:=Registers.pwm(s,channel)
				if oe:
					var mode:=int(regs[1])&3
					if mode>=2 or (mode==1 and (int(regs[1])&4)==0):continue
					level=mode
				if level==0 or int(regs[1])&4:r(out,id+"/pwm"+str(channel),n[11+channel],power if level else ground,50.)
	elif kind=="ws2812" and s.get("powered",false):r(out,id+"/dout",n[3],power if s.get("dout",false) else ground,40.)
	elif kind=="oscillator" and s.get("powered",false) and voltage(v,n[3],ground)>=0.7*voltage(v,power,ground):
		r(out,id+"/clock",n[2],power if fposmod(float(s.get("time",0))*1000000.,1.)<.5 else ground,40.)
	elif kind=="xpt2046" and s.get("powered",false):
		if s.get("selected",false):r(out,id+"/dout",n[4],power if s.get("miso",false) else ground,100.)
		if controls.get("pressed",false):r(out,id+"/irq",n[6],ground,100.)
	return out

static func voltage(v: Dictionary,a: String,b: String) -> float:return float(v[a])-float(v[b]) if v.has(a) and v.has(b) else 0.0
static func tick(device: Dictionary,result: Dictionary,old: Dictionary,dt: float) -> Dictionary:
	if not result.get("ok",false) or not is_finite(dt) or dt<0 or dt>.01:return old.duplicate()
	var kind:=str(device.model);var n: Array=device.nodes
	if n.size()!=Catalog.pins(kind).size():return old.duplicate()
	if not device.get("logical_pins",false):n=Catalog.logical_nodes(kind,n)
	var v: Dictionary=result.get("v",{})
	var ground: String=n[0] if kind=="hd44780" else n[1]
	var power: String=n[1] if kind=="hd44780" else n[0]
	var supply:=voltage(v,power,ground)
	var low:=4.5 if kind in ["hd44780","ws2812"] else 2.3 if kind=="pca9685" else 2.7
	var high:=5.5 if kind in ["hd44780","ws2812","pca9685","oscillator"] else 3.6
	if not is_finite(supply) or supply<low or supply>high:return {"powered":false,"time":float(old.get("time",0))+dt}
	if (kind=="ssd1306" and voltage(v,n[4],ground)<0.3*supply) or (kind=="ili9341" and voltage(v,n[7],ground)<0.3*supply):return {"powered":true,"reset":true,"time":float(old.get("time",0))+dt}
	# Shallow state copy; framebuffer tiles/arrays copy ONLY on writes, never every timestep.
	var s:=old.duplicate()
	if not old.get("powered",false) or old.get("reset",false):
		s=LCD.initial() if kind=="hd44780" else Registers.initial(kind)
		s.time=float(old.get("time",0));s.powered=true
		if kind=="hd44780":s.busy_until=float(s.time)+.01
		if kind=="pca9685":s.ready_at=float(s.time)+.0005
	s.time=float(s.get("time",0))+dt;s.powered=true;s.control=device.get("control",{}).duplicate()
	var p: Array=[]
	for node in n:p.append(voltage(v,str(node),ground))
	var watched: Array=[3,4,5] if kind=="hd44780" else [2,3,4,5] if kind=="ssd1306" else range(2,11) if kind=="pca9685" else [2,3,5,6,7] if kind=="ili9341" else [2,3,5] if kind=="xpt2046" else [2] if kind=="ws2812" else [3] if kind=="oscillator" else []
	if kind=="pca9685" and int(s.registers[0])&64:watched.append(27)
	if kind=="hd44780" and float(p[4])<.6:watched.append_array(range(10 if s.get("four",false) else 6,14))
	for pin in watched:
		var value:=float(p[pin])
		if not is_finite(value) or value<-.3 or value>supply+.3 or (value>(.6 if kind=="hd44780" else supply*.3) and value<(2.2 if kind=="hd44780" else supply*.7)):
			s.io_fault="Invalid logic voltage at pin "+str(pin);s.spi_bits=0;s.spi_byte=0;s.invalid=true
			if s.has("bus"):s.bus=s.bus.duplicate();s.bus.low=false;s.bus.phase="idle"
			return s
	s.io_fault=""
	match kind:
		"hd44780":s.columns=int(device.get("columns",16));s.rows=int(device.get("rows",2));s.backlight=clampf(float(result.get("i",{}).get(str(device.get("id",""))+"/backlight",0))/.02,0,1);LCD.edge(s,p)
		"ssd1306","pca9685":
			var address:=0x3C|(1 if float(p[5])>=0.7*supply else 0) if kind=="ssd1306" else 0x40
			if kind=="pca9685":
				for bit in 6:
					if float(p[5+bit])>=0.7*supply:address|=1<<bit
				if (int(s.registers[0])&80)==0:s.phase_time=float(s.get("phase_time",0))+maxf(0.,float(s.time)-maxf(float(s.time)-dt,float(s.get("ready_at",0))))
				var ext:=float(p[27])>=.7*supply
				if ext and not s.get("ext_high",false) and int(s.registers[0])&64 and (int(s.registers[0])&16)==0:
					s.external_prescale=int(s.get("external_prescale",0))+1
					if int(s.external_prescale)>=int(s.registers[254])+1:s.external_prescale=0;s.external_count=(int(s.get("external_count",0))+1)&4095
				s.ext_high=ext
			I2C.tick(kind,s,float(p[2])>=0.7*supply,float(p[3])>=0.7*supply,address)
		"ili9341","xpt2046":spi(kind,s,p,supply,device.get("control",{}))
		"ws2812":pixels(s,float(p[2])>=0.7*supply)
		"oscillator":s.undersampled=dt>0.00000025
	return s

static func pixels(s: Dictionary,high: bool) -> void:
	var time:=float(s.time);var before:=bool(s.get("high",false))
	if not high and not before and time-float(s.get("fall",time))>=0.00005:
		var bits: Array=s.get("bits",[])
		if bits.size()>=24 and not s.get("invalid",false):
			var output: Array=s.get("pixels",[]).duplicate()
			if output.size()!=24:output.resize(24);output.fill(0)
			for pixel in mini(bits.size()/24,8):
				var channels: Array=[]
				for channel in 3:
					var value:=0
					for bit in 8:value=(value<<1)|int(bits[pixel*24+channel*8+bit])
					channels.append(value)
				output[pixel*3]=channels[1];output[pixel*3+1]=channels[0];output[pixel*3+2]=channels[2]
			s.pixels=output;s.frames=int(s.get("frames",0))+1
		elif not bits.is_empty() and s.get("invalid",false):s.error_frames=int(s.get("error_frames",0))+1
		s.bits=[];s.invalid=false;s.rise=-1.0;s.dout=false
	if high and not before:
		var previous:=float(s.get("rise",-1))
		if previous>=0:
			var period:=time-previous
			if period<0.00000095 or period>0.00000155:s.invalid=true
		s.rise=time
	elif not high and before:
		var width:=time-float(s.get("rise",time));var bit:=-1
		if width>=0.00000025-1e-12 and width<=0.00000055+1e-12:bit=0
		elif width>=0.00000065-1e-12 and width<=0.00000095+1e-12:bit=1
		else:s.invalid=true
		var bits: Array=s.get("bits",[]).duplicate()
		if bits.size()<192:bits.append(maxi(bit,0))
		s.bits=bits;s.fall=time
	s.dout=high and s.get("bits",[]).size()>=192;s.high=high

static func spi(kind: String,s: Dictionary,p: Array,supply: float,control: Dictionary) -> void:
	var selected:=float(p[5])<0.3*supply;var clk:=float(p[2])>=0.7*supply
	if not selected:s.spi_bits=0;s.spi_byte=0;s.response_bits=0;s.miso=false
	elif clk and not s.get("clk",false):
		s.spi_byte=((int(s.get("spi_byte",0))<<1)|(1 if float(p[3])>=0.7*supply else 0))&255
		s.spi_bits=int(s.get("spi_bits",0))+1
		if kind=="xpt2046" and int(s.get("response_bits",0))>0:s.response_bits=int(s.response_bits)-1
		if int(s.spi_bits)==8:
			var byte:=int(s.spi_byte);s.spi_bits=0;s.spi_byte=0
			if kind=="ili9341":Registers.tft(s,float(p[6])>=0.7*supply,byte)
			elif byte&128:
				var channel: int=(byte>>4)&7;var value:=0
				if byte&8 or not channel in [1,3,4,5]:s.unsupported_conversion=true;s.response=0;s.response_bits=0;s.miso=false;s.clk=clk;s.selected=selected;return
				s.unsupported_conversion=false
				if control.get("pressed",false):
					if channel==1:value=roundi(clampf(float(control.get("y",.5)),0,1)*4095)
					elif channel==5:value=roundi(clampf(float(control.get("x",.5)),0,1)*4095)
					elif channel in [3,4]:
						# Fixed400ohm sheet/100ohm pressed contact equivalent divider.
						var rx:=400.*maxf(.001,float(control.get("x",.5)))
						var z1:=4095.*rx/(rx+100.+400.)
						value=roundi(z1 if channel==3 else z1*(1.+100./rx))
				s.response=value<<3;s.response_bits=16
	elif not clk and s.get("clk",false) and kind=="xpt2046":
		var bits:=int(s.get("response_bits",0))
		s.miso=bits>0 and (int(s.get("response",0))&(1<<maxi(bits-1,0)))!=0
	s.clk=clk;s.selected=selected

static func opamp(kind: String,id: String,n: Array,v: Dictionary) -> Array:
	var low: String=n[3] if kind=="lm358" else n[10]
	var high: String=n[7] if kind=="lm358" else n[3]
	var supply:=voltage(v,high,low)
	var groups: Array=[[2,1,0],[4,5,6]] if kind=="lm358" else [[2,1,0],[4,5,6],[9,8,7],[11,12,13]]
	var out: Array=[]
	r(out,id+"/power",high,low,15000.)
	for i in groups.size():
		var pins: Array=groups[i];var plus:=voltage(v,n[pins[0]],low);var minus:=voltage(v,n[pins[1]],low)
		for pin in [pins[0],pins[1]]:r(out,id+"/bias"+str(pin),n[pin],low,1e8)
		if not is_finite(supply) or not is_finite(plus) or not is_finite(minus) or supply<3 or supply>30 or plus<0 or minus<0 or plus>supply-1.5 or minus>supply-1.5:
			r(out,id+"/off"+str(i),n[pins[2]],low,1e12);continue
		var lo:=id+"/lo"+str(i);var hi:=id+"/hi"+str(i)
		out.append({"id":id+"/lowrail"+str(i),"kind":"V","a":lo,"b":low,"value":.02,"resistance":0.})
		out.append({"id":id+"/highrail"+str(i),"kind":"V","a":high,"b":hi,"value":1.5,"resistance":0.})
		out.append({"id":id+"/amp"+str(i),"kind":"E","a":n[pins[2]],"b":lo,"cp":n[pins[0]],"cn":n[pins[1]],"high":hi,"gain":100000.,"resistance":50.})
	return out
