extends RefCounted
const Devices=preload("res://scripts/commercial_devices/peripherals.gd")
const Catalog=preload("res://scripts/commercial_devices/catalog.gd")
## Native scheduling owner consumes these relative deadlines alongside CPU barriers.
## It must solve output changes before CPU resumes; no production solver lives here.
static func max_step(device: Dictionary,state: Dictionary) -> float:
	if not state.get("powered",false):return INF
	var kind:=str(device.get("model",""))
	var time:=float(state.get("time",0))
	if kind=="oscillator":return maxf(1e-12,(floor(time*2000000.)+1.)/2000000.-time)
	if kind=="ws2812" and not state.get("high",false) and not state.get("bits",[]).is_empty():return maxf(1e-12,float(state.get("fall",time))+.00005-time)
	if kind=="hd44780" and float(state.get("busy_until",0))>time:return float(state.busy_until)-time
	if kind=="pca9685" and not state.get("extclk_unsupported",false):
		if float(state.get("ready_at",0))>time:return float(state.ready_at)-time
		var regs: Array=state.get("output_registers",state.get("registers",[]))
		if regs.size()!=256 or int(regs[0])&80:return INF
		var quantum:=(int(regs[254])+1)/25000000.0
		var counter:=float(state.get("phase_time",0))/quantum
		var count:=int(floor(counter))&4095
		var delay:=INF
		for channel in 16:
			var base:=6+channel*4
			if int(regs[base+1])&16 or int(regs[base+3])&16:continue
			var on: int=int(regs[base])|((int(regs[base+1])&15)<<8)
			var off: int=int(regs[base+2])|((int(regs[base+3])&15)<<8)
			if on==off:continue
			for edge in [on,off]:
				var ticks:=posmod(int(edge)-count,4096)
				if ticks==0:ticks=4096
				delay=minf(delay,(float(ticks)-fposmod(counter,1.))*quantum)
		return maxf(delay,1e-12)
	return INF

static func input_nodes(device: Dictionary) -> Array:
	var n: Array=device.get("nodes",[])
	match str(device.get("model","")):
		"hd44780":return n.slice(3,14)
		"ssd1306":return n.slice(2,6)
		"pca9685":return n.slice(2,11)+[n[27]]
		"ili9341":return [n[2],n[3],n[5],n[6],n[7]]
		"xpt2046":return [n[2],n[3],n[5]]
		"ws2812":return [n[2]]
	return []

## After each native-edge solve, observe at the SAME time before any CPU samples.
## If changed, re-expand/re-solve and observe again; the integrator bounds settling.
static func observe(parts: Array,result: Dictionary,states: Dictionary) -> Dictionary:
	var updates:={};var changed:=false
	for device in parts:
		if device.get("kind","")!="io_device" or not Catalog.supports(str(device.get("model",""))):continue
		var old: Dictionary=states.get(device.id,{})
		var next:=Devices.tick(device,result,old,0.0)
		if next!=old:updates[device.id]=next;changed=true
	return {"changed":changed,"updates":updates}

static func next_delay(parts: Array,states: Dictionary,maximum: float) -> float:
	var delay:=maximum
	for device in parts:
		if device.get("kind","")=="io_device" and Catalog.supports(str(device.get("model",""))):delay=minf(delay,max_step(device,states.get(device.id,{})))
	return delay
