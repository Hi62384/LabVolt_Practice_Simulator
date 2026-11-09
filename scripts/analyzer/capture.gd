extends RefCounted
## Read-only measurements. Never interpolates missing solver or network samples.
var positive := ""
var negative := "B2"
var samples: Array=[]
var held := false
var threshold := 2.5
var capacity := 1024
func probes(a: String,b: String) -> void:
	if positive==a and negative==b:return
	positive=a;negative=b;samples.clear()
static func differential(result: Dictionary,a: String,b: String) -> Dictionary:
	if not result.get("ok",false):return {"ok":false,"reason":str(result.get("error","No live solution"))}
	var v: Dictionary=result.get("v",{});var islands: Dictionary=result.get("islands",{})
	if not v.has(a) or not v.has(b):return {"ok":false,"reason":"Probe node not measured"}
	if not islands.has(a) or not islands.has(b) or islands[a]!=islands[b]:return {"ok":false,"reason":"Floating probes: no shared electrical reference"}
	return {"ok":true,"value":float(v[a])-float(v[b])}
func ingest(result: Dictionary) -> void:
	if held or positive.is_empty() or not result.has("time"):return
	var t := float(result.time)
	if not is_finite(t):return
	if not samples.is_empty():
		if t<float(samples[-1].time):samples.clear()
		elif t==float(samples[-1].time):return
	var measured := differential(result,positive,negative)
	samples.append({"time":t,"valid":measured.ok,"value":float(measured.get("value",0))})
	if samples.size()>capacity:samples.pop_front()
func statistics() -> Dictionary:
	var result := {"count":samples.size(),"timing":false}
	if samples.size()<2:return result
	var low := INF;var high := -INF;var area := 0.0;var square_area := 0.0;var high_time := 0.0;var rises: Array=[];var max_dt := 0.0
	for sample in samples:
		if not sample.valid:return result # a gap invalidates timing, never bridge it
		low=minf(low,sample.value);high=maxf(high,sample.value)
	for index in range(1,samples.size()):
		var a: Dictionary=samples[index-1];var b: Dictionary=samples[index]
		var dt := float(b.time)-float(a.time)
		max_dt=maxf(max_dt,dt);area+=float(a.value)*dt
		square_area+=float(a.value)*float(a.value)*dt
		if float(a.value)>=threshold:high_time+=dt
		if float(a.value)<threshold and float(b.value)>=threshold:rises.append(float(b.time))
	var duration := float(samples[-1].time)-float(samples[0].time)
	result.merge({"min":low,"max":high,"mean":area/duration,"rms":sqrt(square_area/duration),"duration":duration,"max_dt":max_dt,"high_fraction":high_time/duration})
	# At least two complete cycles, each with eight or more received samples.
	if rises.size()>=3 and high-low>.05:
		var period := (float(rises[-1])-float(rises[0]))/(rises.size()-1)
		if period>=8*max_dt:
			var cycle_high := 0.0
			for index in range(1,samples.size()):
				var a: Dictionary=samples[index-1];var b: Dictionary=samples[index]
				if a.time>=rises[0] and b.time<=rises[-1] and float(a.value)>=threshold:cycle_high+=float(b.time)-float(a.time)
			result.merge({"timing":true,"period":period,"frequency":1.0/period,"duty":cycle_high/(float(rises[-1])-float(rises[0]))},true)
	return result
static func connected_nodes(board: Dictionary,start: String) -> Dictionary:
	const Board=preload("res://scripts/breadboard_model.gd")
	var visited := {start:true};var pending := [start]
	while not pending.is_empty():
		var n: String=pending.pop_back()
		for wire in board.get("wires",[]):
			var a := Board.node(str(wire[0]),int(board.rows));var b := Board.node(str(wire[1]),int(board.rows))
			var next := b if n==a else a if n==b else ""
			if next!="" and not visited.has(next):visited[next]=true;pending.append(next)
	return visited
static func diagnostics(board: Dictionary,result: Dictionary,states: Dictionary,selected: Array) -> Array:
	const Board=preload("res://scripts/breadboard_model.gd")
	var messages: Array=[]
	if not result.get("ok",false):messages.append(str(result.get("error","No live solution; deploy or open the circuit designer.")));return messages
	for id in result.get("mode",{}):
		if result.mode[id]=="CC":messages.append(str(id)+": current limiting; inspect overload/short circuit")
	for part in board.parts:
		if not selected.has(part.id):continue
		var id := "board/"+str(part.id)
		var model: Dictionary=Board.catalog(board).get(str(part.type),{})
		if result.get("i",{}).has(id) and result.get("drop",{}).has(id):
			var power := absf(float(result.i[id])*float(result.drop[id]))
			var limit := float(model.get("max_power_w",.25 if model.get("kind","")=="R" and "0.25 W" in str(model.get("rating","")) else 0))
			if limit>0 and power>limit:messages.append(str(part.id)+": %.4f W exceeds catalog %.4f W rating"%[power,limit])
			if model.get("kind","")=="LED" and absf(float(result.i[id]))>.02:messages.append(str(part.id)+": current exceeds catalog 20 mA nominal")
		var pins: Array=Board.pins(part)
		if pins.size()==2:
			var a := Board.node(str(pins[0]),int(board.rows));var b := Board.node(str(pins[1]),int(board.rows))
			if connected_nodes(board,a).has(b):messages.append(str(part.id)+": pins shorted together by strips/jumpers (bypassed)")
			elif result.get("i",{}).has(id) and absf(float(result.i[id]))<1e-9 and absf(float(result.get("drop",{}).get(id,0)))>.05:messages.append(str(part.id)+": voltage present, no measurable conduction (open/off path)")
		if states.has(id) and states[id].has("powered") and not states[id].powered:messages.append(str(part.id)+": backend reports unpowered")
		if result.get("drop",{}).has(id) and result.get("i",{}).has(id) and absf(float(result.drop[id]))<1e-6 and absf(float(result.i[id]))<1e-9:messages.append(str(part.id)+": no measured excitation; check source and return")
	return messages
