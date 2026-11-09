extends RefCounted
const Catalog = preload("res://scripts/electronics_catalog.gd")
const Custom=preload("res://scripts/custom_circuit.gd")
const BASE_HOLES := "PNABCDEFGHIJ"
const LOWER_HOLES := "WXKLMOQRSTUV"
const OUTER_RAILS := "YZ"
const RAIL_HOLES := "PNWXYZ"
const Sources = preload("res://scripts/electronics/portable_sources.gd")
const Debug = preload("res://scripts/electronics/circuit_workspace/debug_instruments.gd")
static func hole_letters(board: Dictionary) -> String:
	return BASE_HOLES+LOWER_HOLES+OUTER_RAILS if board.get("expanded",false) else BASE_HOLES+"WX"
static func catalog(board: Dictionary) -> Dictionary:
	var entries := preload("res://scripts/electronics/component_values/values.gd").augment(Custom.catalog(board.get("definitions",{})),board.get("parts",[]).map(func(part):return str(part.get("type",""))))
	if Debug.contains(board):entries.merge(Debug.entries())
	return entries
static func pins(part: Dictionary) -> Array:return part.get("pins",[part.get("a",""),part.get("b","")])
static func manual_input_type(type: String) -> String:
	if type in ["button","toggle","pot10k","variable_cap","variable_inductor","photodiode","solar_panel"]:return type
	if type in Sources.CONTROLS:return type
	if type.begins_with("cv1:"):
		var entry := Catalog.simulation_entry(type)
		if entry.get("kind","")=="pot":return "pot10k"
		var mode := str(entry.get("source_mode",""))
		if mode in Sources.CONTROLS:return mode
	return ""
static func empty() -> Dictionary:
	return {"version":1,"rows":30,"parts":[],"wires":[],"ports":["P1","N1","A1","F1"]}
static func node(hole: String,rows := 30) -> String:
	return preload("res://scripts/package_editor/package_geometry.gd").electrical_node(hole,rows)
static func valid_hole(board: Dictionary,hole: String) -> bool:
	return not hole.is_empty() and hole.left(1) in hole_letters(board) and not node(hole,int(board.rows)).is_empty()

static func fit_external_ports(board: Dictionary, current_ports: Array, attached_ports: Array) -> String:
	var defaults: Array = empty().ports
	if current_ports.size() != defaults.size():
		return "Four external ports required"
	var ports := current_ports.duplicate()
	for slot in ports.size():
		var hole := str(ports[slot])
		if valid_hole(board, hole):
			continue
		if ("B" + str(slot + 1)) in attached_ports:
			return "Disconnect the lab lead at %s before resizing." % hole
		ports[slot] = defaults[slot]
	board.ports = ports
	return ""

static func wire_key(wire: Array) -> String:
	var a := str(wire[0])
	var b := str(wire[1])
	return a+"|"+b if a<b else b+"|"+a

static func validate(board: Dictionary,available: Dictionary={},unlimited := false) -> String:
	if int(board.get("rows",0)) not in [10,20,30,40,50,60]:return "Board size must be between 10 and 60 rows."
	if not board.get("expanded",false) is bool:return "Invalid board expansion"
	if not board.get("parts") is Array or not board.get("wires") is Array:return "Invalid board data"
	if board.parts.size()>48 or board.wires.size()>96:return "Board simulation budget exceeded"
	if not board.get("controls",{}) is Dictionary or board.get("controls",{}).size()>64:return "Invalid input controls"
	for control in board.get("controls",{}).values():
		if not control is Dictionary:return "Invalid input state"
		for key in control:
			if key in ["source_voltage","source_frequency","source_wave"]:
				var value: Variant=control[key]
				if not (value is float or value is int) or not is_finite(float(value)):return "Invalid source setting"
				if key=="source_voltage" and (value<0 or value>Sources.MAX_VOLTAGE):return "Invalid source voltage"
				if key=="source_frequency" and (value<Sources.MIN_FREQUENCY or value>Sources.MAX_FREQUENCY):return "Invalid source frequency"
				if key=="source_wave" and (value!=int(value) or value<0 or value>=Sources.WAVES.size()):return "Invalid waveform"
				continue
			if key not in ["pressed","setting"]:return "Unsupported input setting"
			if key=="setting" and (not (control[key] is float or control[key] is int) or not is_finite(float(control[key])) or float(control[key])<0 or float(control[key])>1):return "Invalid potentiometer setting"
			if key=="pressed" and not control[key] is bool:return "Invalid button setting"
	if not board.get("programs",{}) is Dictionary or board.get("programs",{}).size()>16:return "Invalid device programs"
	for program in board.get("programs",{}).values():
		if not program is Dictionary or not program.get("run",true) is bool:return "Invalid device program"
		if not preload("res://scripts/inventory_authority/firmware_schema.gd").part(program):return "Invalid device source or compiled image"
		if not preload("res://scripts/firmware_runtime.gd").compile(str(program.get("firmware",""))).ok:return "Invalid embedded firmware"
	var catalog := catalog(board);var ids := {};var counts := {};var holes := {};var expanded_count := 0
	for p in board.parts:
		if not p is Dictionary:return "Invalid component"
		if not preload("res://scripts/inventory_authority/firmware_schema.gd").part(p):return "Invalid component firmware"
		if p.has("surface_rotation") and (not (p.surface_rotation is int or p.surface_rotation is float) or not is_finite(float(p.surface_rotation))):return "Invalid surface rotation"
		var type := str(p.get("type",""));var id := str(p.get("id",""))
		if not catalog.has(type) or id=="" or ids.has(id):return "Unknown or duplicate component"
		if type=="lv_mcu":
			var compiled := preload("res://scripts/firmware_runtime.gd").compile(str(p.get("firmware",preload("res://scripts/firmware_runtime.gd").TEMPLATE)))
			if not compiled.ok:return "Firmware line %d: %s"%[compiled.line,compiled.error]
		ids[id]=true;counts[type]=int(counts.get(type,0))+1
		var simulation_tool := type in [Debug.SOURCE,Debug.METER]
		if simulation_tool and not Debug.valid(p):return "Invalid simulation instrument settings"
		if not simulation_tool and not unlimited and counts[type]>int(available.get(type,0)):return "Kit does not contain enough "+catalog[type].name
		if type.begins_with("ic:"):
			var error := Custom.validate(type,board.get("definitions",{}))
			if error!="":return error
			if pins(p).size()!=catalog[type].pins.size():return "Custom IC footprint has the wrong number of pins"
			var flat := Custom.flatten(type,board.definitions,"validation/",pins(p))
			expanded_count+=flat.parts.size()
		else:
			if pins(p).size()!=catalog[type].pins.size():return "Component pin count mismatch"
			expanded_count+=Debug.expand(type,id,pins(p),p,0.0).size() if simulation_tool else preload("res://scripts/device_models.gd").expand(catalog[type],id,pins(p),p).size()
		if expanded_count>64:return "Board exceeds 64 expanded components"
		for pin in pins(p):
			var hole := str(pin)
			if not valid_hole(board,hole) or holes.has(hole):return "Occupied or invalid component hole"
			holes[hole]=true
	if board.get("standalone",false):
		if board.parts.size()!=1 or not board.wires.is_empty() or board.get("definitions",{}).get(str(board.parts[0].type),{}).get("package","")!="PCB":return "Standalone circuits require exactly one PCB"
	for package in board.parts:
		if board.get("standalone",false):continue
		if str(package.type)=="solar_panel" and package.get("solar_footprint",false):
			var turns := roundi(float(package.get("surface_rotation",0.0))/(PI*.5))
			var pin_one := grid(str(pins(package)[0]))
			if grid(str(pins(package)[1])) != pin_one + solar_offset(Vector2i.RIGHT, turns):
				return "Solar panel pins must be adjacent along the panel edge"
			var footprint := solar_body(package)
			var pin_two := grid(str(pins(package)[1]))
			var occupied := footprint.merge(Rect2i(pin_one.min(pin_two),(pin_one-pin_two).abs()+Vector2i.ONE))
			var strip := posmod(occupied.position.y,12)
			if occupied.position.x<0 or occupied.end.x>int(board.rows) or occupied.position.y<0 or occupied.end.y>(24 if board.get("expanded",false) else 12) or strip<2 or strip+occupied.size.y>(7 if strip<7 else 12):
				return "Solar panel needs a 2 × 2 body and two adjacent pin holes on one terminal strip"
			for other in board.parts:
				if other.id==package.id:continue
				var other_definition: Dictionary=board.get("definitions",{}).get(str(other.type),{})
				if other.get("solar_footprint",false) and str(other.type)=="solar_panel" and occupied.intersects(solar_body(other)):
					return "Solar panel overlaps another solar panel"
				if other_definition.has("footprint") and occupied.intersects(package_rect(other,other_definition)):
					return "Solar panel overlaps a PCB footprint"
				for pin in pins(other):
					if footprint.has_point(grid(str(pin))):return "Solar panel overlaps another component"
			for wire in board.wires:
				if wire is Array and wire.size()==2:
					for hole in wire:
						if footprint.has_point(grid(str(hole))):return "Solar panel covers a jumper hole"
		elif str(package.type)=="solar_panel":
			var terminals := pins(package)
			var a := grid(str(terminals[0]))
			var b := grid(str(terminals[1]))
			var covered := Rect2i(a,Vector2i.ONE).expand(b)
			var footprint := Rect2i(covered.position-Vector2i.ONE,covered.size+Vector2i(2,2))
			if footprint.position.x<0 or footprint.position.y<0 or footprint.end.x>int(board.rows) or footprint.end.y>(24 if board.get("expanded",false) else 12):
				return "Solar panel needs one free hole around its terminals"
			if footprint.position.y<12 and footprint.end.y>12:return "Solar panel must fit on one bank"
			for other in board.parts:
				if other.id==package.id:continue
				for pin in pins(other):
					if footprint.has_point(grid(str(pin))):return "Solar panel overlaps another component"
		var definition: Dictionary=board.get("definitions",{}).get(str(package.type),{})
		if not definition.has("footprint"):continue
		var footprint := package_rect(package,definition)
		if not preload("res://scripts/package_editor/package_geometry.gd").placement(package,definition).ok:return "Package pins do not match the saved physical grid positions"
		var row_limit := 24 if board.get("expanded",false) else 12
		if footprint.position.x<0 or footprint.position.y<0 or footprint.end.x>int(board.rows) or footprint.end.y>row_limit or (footprint.position.y<12 and footprint.end.y>12):return "PCB footprint must fit on one bank"
		for pin in pins(package):
			if not footprint.has_point(grid(str(pin))):return "PCB pins must lie inside its footprint"
		for other in board.parts:
			if other.id==package.id:continue
			var other_definition: Dictionary=board.get("definitions",{}).get(str(other.type),{})
			if other_definition.has("footprint") and footprint.intersects(package_rect(other,other_definition)):return "PCB footprints overlap"
			for pin in pins(other):
				if footprint.has_point(grid(str(pin))):return "Component overlaps a PCB footprint"
	for wire in board.wires:
		if not wire is Array or wire.size()!=2:return "Invalid jumper"
		for hole in wire:
			if not valid_hole(board,str(hole)):return "Jumper outside board"
	var colors: Variant = board.get("wire_colors",{})
	if not colors is Dictionary or colors.size()>96:return "Invalid wire colors"
	for key in colors:
		if not key is String or not colors[key] is String or not Color.html_is_valid(colors[key]):return "Invalid wire color"
	if not board.get("ports") is Array or board.ports.size()!=4:return "Four external ports required"
	for hole in board.ports:
		if not valid_hole(board,str(hole)):return "External port outside board"
	var io_error := validate_io_controls(board.get("io_controls",{}),board.parts,board.get("definitions",{}))
	if io_error!="":return io_error
	return ""
static func expand(board: Dictionary,prefix := "board/",voltages: Dictionary={},runtime: Dictionary={}) -> Dictionary:
	runtime=runtime.duplicate();runtime["__resistors"]=preload("res://scripts/physical_resistors.gd").parameters(board);runtime["__inputs"]=board.get("controls",{}).duplicate(true);runtime["__inputs"].merge(io_inputs(board),true);runtime["__programs"]=board.get("programs",{})
	var parts: Array=[];var wires: Array=[];var override_catalog: Dictionary={}
	for p in board.parts:
		if str(p.type).begins_with("ic:"):
			var nested := Custom.flatten(p.type,board.definitions,prefix+str(p.id)+"/",pins(p).map(func(h):return prefix+node(h,int(board.rows))),voltages,runtime)
			parts.append_array(nested.parts);wires.append_array(nested.wires);continue
		if str(p.type) in [Debug.SOURCE,Debug.METER]:
			parts.append_array(Debug.expand(str(p.type),prefix+str(p.id),pins(p).map(func(h):return prefix+node(h,int(board.rows))),p,float(runtime.get("__simulation_time",0))))
			continue
		var definition: Dictionary
		if board.get("definitions",{}).has(p.type):
			if override_catalog.is_empty():override_catalog=catalog(board)
			definition=override_catalog[p.type]
		else:definition=Catalog.simulation_entry(str(p.type))
		parts.append_array(preload("res://scripts/device_models.gd").expand(definition,prefix+str(p.id),pins(p).map(func(h):return prefix+node(h,int(board.rows))),p,voltages,runtime))
	wires.append_array(_external_wires(board,prefix))
	return {"parts":parts,"wires":wires}
static func _external_wires(board: Dictionary,prefix: String) -> Array:
	var wires: Array=[]
	for w in board.wires:wires.append([prefix+node(w[0],int(board.rows)),prefix+node(w[1],int(board.rows))])
	for i in range(4):wires.append(["B%d"%(i+1),prefix+node(board.ports[i],int(board.rows))])
	if board.get("standalone",false) and board.parts.size()==1:
		for i in pins(board.parts[0]).size():wires.append(["X%d"%(i+1),prefix+node(str(pins(board.parts[0])[i]),int(board.rows))])
	return wires
static func wires_only(board: Dictionary,prefix := "board/") -> Array:
	# Nested packages and routed PCBs retain their original full expansion.
	for part in board.parts:
		if str(part.type).begins_with("ic:"):return expand(board,prefix).wires
	# Built-in device expansion contributes parts only. Read current wiring data
	# on every call; do not cache topology, controls, device state or timestamps.
	return _external_wires(board,prefix)

static func blueprint(board: Dictionary,title: String) -> Dictionary:
	var bp := {"name":title.left(40),"revision":1,"parts":[],"wires":[],"pins":[]}
	bp.programs={}
	bp.io_controls={}
	for key in board.get("io_controls",{}):bp.io_controls[str(key).trim_prefix("board/")]=board.io_controls[key].duplicate(true)
	for key in board.get("programs",{}):bp.programs[str(key).trim_prefix("board/")]=board.programs[key].duplicate(true)
	for p in board.parts:
		if str(p.type).begins_with("ic:"):bp.parts.append({"id":p.id,"type":p.type,"firmware":str(p.get("firmware",preload("res://scripts/firmware_runtime.gd").TEMPLATE)) if p.type=="lv_mcu" else "","run":p.get("run",true),"nodes":pins(p).map(func(h):return node(h,int(board.rows)))})
		else:bp.parts.append({"id":p.id,"type":p.type,"a":node(p.a,int(board.rows)),"b":node(p.b,int(board.rows)),"pressed":p.get("pressed",false),"setting":p.get("setting",.5),"firmware":str(p.get("firmware",preload("res://scripts/firmware_runtime.gd").TEMPLATE)) if p.type=="lv_mcu" else "","run":p.get("run",true),"nodes":pins(p).map(func(h):return node(h,int(board.rows)))})
		for key in ["io_input","surface_rotation","source_voltage","source_frequency","source_wave"]:
			if p.has(key):bp.parts[-1][key]=p[key]
		for field in ["code_files","native_sources","native_firmware"]:
			if p.get(field) is Dictionary:bp.parts[-1][field]=p[field].duplicate(true)
	for wire in board.wires:bp.wires.append([node(wire[0],int(board.rows)),node(wire[1],int(board.rows))])
	for i in board.ports.size():bp.pins.append({"name":"Pin "+str(i+1),"node":node(board.ports[i],int(board.rows))})
	return bp

static func grid(hole: String) -> Vector2i:return Vector2i(int(hole.substr(1))-1,(BASE_HOLES+LOWER_HOLES+OUTER_RAILS).find(hole.left(1)))
static func solar_offset(offset: Vector2i, turns: int) -> Vector2i:
	return preload("res://scripts/package_editor/package_geometry.gd").rotate(offset,turns)

static func solar_body(part: Dictionary) -> Rect2i:
	var origin := grid(str(pins(part)[0]))
	var turns := roundi(float(part.get("surface_rotation",0.0))/(PI*.5))
	var first := origin+solar_offset(Vector2i(0,1),turns)
	var last := origin+solar_offset(Vector2i(1,2),turns)
	return Rect2i(first.min(last),(first-last).abs()+Vector2i.ONE)

static func package_rect(part: Dictionary,definition: Dictionary) -> Rect2i:
	return preload("res://scripts/package_editor/package_geometry.gd").placement(part,definition).get("rect",Rect2i())

static func devices(board: Dictionary) -> Array:
	var result: Array=[]
	collect_devices(board.get("parts",[]),board.get("definitions",{}),"board/",result,0)
	return result
static func collect_devices(parts: Array,definitions: Dictionary,prefix: String,result: Array,depth: int) -> void:
	if depth>8:return
	for part in parts:
		var id := prefix+str(part.id)
		if str(part.type).begins_with("ic:"):
			if definitions.has(part.type):collect_devices(definitions[part.type].parts,definitions,id+"/",result,depth+1)
		else:result.append({"id":id,"part":part})

static func standalone(id: String,definitions: Dictionary) -> Dictionary:
	if not Custom.is_pcb(id,definitions) or Custom.validate(id,definitions)!="":return {}
	var board := empty();board.standalone=true
	board.definitions={}
	var pending: Array[String]=[id]
	while not pending.is_empty():
		var type: String=pending.pop_back()
		if board.definitions.has(type):continue
		var blueprint: Dictionary=definitions[type]
		board.definitions[type]=blueprint.duplicate(true)
		for part in blueprint.parts:
			var dependency := str(part.type)
			if dependency.begins_with("ic:") and definitions.has(dependency):
				pending.append(dependency)
	board.rows=40
	var holes: Array=[]
	for i in definitions[id].pins.size():holes.append(("A" if i<40 else "F")+str(i%40+1))
	board.parts=[{"id":"pcb","type":id,"a":holes[0],"b":holes[-1],"pins":holes}]
	return board

static func io_inputs(board: Dictionary) -> Dictionary:
	var result := {}
	collect_io_defaults(board.get("parts",[]),board.get("definitions",{}),"board/",result,0)
	result.merge(board.get("io_controls",{}),true)
	return result
static func collect_io_defaults(parts: Array,definitions: Dictionary,prefix: String,result: Dictionary,depth: int) -> void:
	if depth>=8:return
	for part in parts:
		var id := prefix+str(part.id)
		if part.get("io_input") is Dictionary:result[id]=part.io_input.duplicate(true)
		var bp: Dictionary=definitions.get(str(part.type),{})
		if bp.is_empty():continue
		collect_io_defaults(bp.get("parts",[]),definitions,id+"/",result,depth+1)
		for key in bp.get("io_controls",{}):result[id+"/"+str(key)]=bp.io_controls[key].duplicate(true)
static func validate_io_controls(saved: Variant,parts: Array,definitions: Dictionary,prefix: String="board/") -> String:
	if not saved is Dictionary or saved.size()>64:return "Invalid I/O controls"
	if ResourceLoader.exists("res://scripts/io_devices/host_adapter.gd"):
		var adapter=load("res://scripts/io_devices/host_adapter.gd")
		return adapter.validate_controls(saved,adapter.kinds(parts,definitions,prefix))
	# Optional package may be absent: preserve bounded scalar metadata, never execute it.
	for id in saved:
		if not id is String or not saved[id] is Dictionary or saved[id].size()>8:return "Invalid I/O control metadata"
		for key in saved[id]:
			if key not in ["revision","detent","keys","x","y","pressed","position"]:return "Unknown I/O input field"
			var value=saved[id][key]
			if key=="pressed":
				if not value is bool:return "Invalid I/O switch"
			elif not (value is int or value is float) or not is_finite(float(value)):return "Invalid I/O number"
	return ""
