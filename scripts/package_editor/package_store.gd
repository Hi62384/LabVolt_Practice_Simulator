extends RefCounted
## Owns extended editor saves without changing the existing profile API.
const Board=preload("res://scripts/breadboard_model.gd")
const Custom=preload("res://scripts/custom_circuit.gd")
static func save_package(profile: RefCounted,options: Dictionary,pins: Array) -> String:
	var prepared := prepare_package(profile, options, pins)
	if prepared.has("error"):return prepared.error
	var before: Dictionary=profile.data.duplicate(true)
	profile.data.blueprints=prepared.definitions
	if profile.save()!=OK:profile.data=before;return "Save failed; package unchanged"
	return "Blueprint saved: "+str(prepared.name)

static func prepare_package(profile: RefCounted,options: Dictionary,pins: Array) -> Dictionary:
	if not profile.data.get("pending_trade",{}).is_empty():return {"error":"Finish the pending trade first"}
	var design: Dictionary=profile.data.kits[profile.data.equipped].board
	if Board.Debug.contains(design):return {"error":"Remove simulation instruments before building an IC or PCB."}
	var error := Board.validate(design,{},true)
	if error!="":return {"error":error}
	if str(options.get("name","")).strip_edges().is_empty():return {"error":"Enter a circuit name"}
	var bp := Board.blueprint(design,str(options.name))
	options = options.duplicate(true)
	for key in ["name", "description", "package", "footprint", "marking", "orientation_marker", "exposed"]:
		if options.has(key):
			bp[key] = options[key]
	bp.layout={"rows":design.rows,"parts":design.parts.duplicate(true),"wires":design.wires.duplicate(true)}
	bp.pins=[]
	for pin in pins:
		var node := Board.node(str(pin.get("hole","")),int(design.rows))
		if node=="":return {"error":"Pin %s needs a valid internal breadboard hole" % pin.get("name", pin.get("id", ""))}
		var mapped: Dictionary=pin.duplicate(true);mapped.erase("hole");mapped.node=node;bp.pins.append(mapped)
	var definitions: Dictionary=profile.data.get("blueprints",{}).duplicate(true)
	var id := "ic:"+JSON.stringify(bp).sha256_text().left(24)
	definitions[id]=bp
	error=Custom.validate(id,definitions)
	if error!="":return {"error":error}
	return {"definitions":definitions, "name":bp.name}
