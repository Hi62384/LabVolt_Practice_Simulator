extends RefCounted
const POWER_RATINGS := [.25,.5,1.0,2.0,5.0,10.0,25.0,50.0,100.0]
## Manufacturing values are allocated by the host and persist with the owned unit.
static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=6 or value.get("schema")!=1 or value.get("model")!="resistor":return false
	for key in ["nominal","tolerance","actual","watts"]:
		if not (value.get(key) is float or value.get(key) is int) or not is_finite(float(value[key])):return false
	return float(value.nominal)>0 and float(value.nominal)<=1e9 and float(value.tolerance)>0 and float(value.tolerance)<=0.2 and float(value.watts)>0 and float(value.watts)<=100 and absf(float(value.actual)-float(value.nominal))<=float(value.nominal)*float(value.tolerance)+1e-8

static func ensure(profile: Dictionary,design: Dictionary,unavailable: Array = []) -> bool:
	var catalog: Dictionary=preload("res://scripts/electronics/component_values/values.gd").augment(load("res://scripts/electronics_catalog.gd").all(),profile.get("inventory",{}).keys())
	var wanted := {}
	for part in design.get("parts",[]):
		if catalog.get(part.type,{}).get("physical_resistor",false):wanted[part.type]=int(wanted.get(part.type,0))+1
	var owned: Dictionary=profile.get("component_instances",{}).duplicate(true)
	var changed := false
	for type in wanted:
		var available: int=int(profile.get("inventory",{}).get(type,0))
		var count := 0
		var total := 0
		for unit in owned:
			if owned[unit].type!=type:continue
			total+=1
			if unit not in unavailable:count+=1
		while count<int(wanted[type]) and total<available and owned.size()<1000:
			var model: Dictionary=catalog[type]
			var bytes := Crypto.new().generate_random_bytes(20)
			var unit := bytes.slice(0,16).hex_encode()
			var fraction := float(bytes.decode_u32(16))/4294967295.0*2-1
			var parameters := {"schema":1,"model":"resistor","nominal":float(model.value),"tolerance":float(model.resistance_tolerance),"actual":float(model.value)*(1+fraction*float(model.resistance_tolerance)),"watts":float(model.power_rating_w)}
			owned[unit]={"type":type,"root":"board/unit","component_runtime":{"board/unit":parameters}}
			count+=1;total+=1;changed=true
	if changed:profile.component_instances=owned
	return changed

static func parameters(board: Dictionary) -> Dictionary:
	var result := {}
	for id in board.get("component_runtime",{}):
		var value: Variant=board.component_runtime[id]
		if valid(value):result[id]=value
	return result

static func catalog_entries() -> Dictionary:
	var entries := {}
	for resistance in [100,220,470,1000,2200,4700,10000,47000,100000]:
		for tolerance in [0.01,0.05]:
			for watts in POWER_RATINGS:
				var id := "r%d_t%d_w%d"%[resistance,int(tolerance*100),int(watts*100)]
				entries[id]={"name":"%d Ω · ±%d%% · %.2f W"%[resistance,int(tolerance*100),watts],"category":"Basic","kind":"R","value":float(resistance),"unit":"Ω","resistance_tolerance":tolerance,"power_rating_w":watts,"physical_resistor":true,"rating":"Owned measured value persists within tolerance. Overrating is indicated from actual V×I; no thermal damage model.","price":2+int(watts*2)+(1 if tolerance<0.02 else 0),"space":1,"rarity":"Common","pins":["1","2"]}
	return entries

