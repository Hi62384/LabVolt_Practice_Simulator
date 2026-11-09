extends RefCounted
const Catalog=preload("res://scripts/electronics_catalog.gd")
const PCB=preload("res://scripts/pcb_design/design.gd")
const Surface=preload("res://scripts/pcb_design/surface_layout.gd")
const Geometry=preload("res://scripts/package_editor/package_geometry.gd")
static func is_pcb(id: String, definitions: Dictionary) -> bool:
	var blueprint: Variant=definitions.get(id)
	return blueprint is Dictionary and blueprint.get("package","")=="PCB"

static func catalog(definitions: Dictionary) -> Dictionary:
	var result := Catalog.all()
	for id in definitions:
		var bp=definitions[id]
		if not bp is Dictionary or not bp.get("pins") is Array or bp.pins.any(func(pin):return not pin is Dictionary):continue
		result[id]={"name":str(bp.get("name","Custom IC")),"kind":"module","category":str(bp.get("package","IC")),"space":6 if bp.get("package","IC")=="PCB" else 3,"rarity":"Custom","price":0,"rating":"Reusable circuit · revision %d"%int(bp.get("revision",1)),"pins":bp.get("pins",[]).map(func(pin):return str(pin.get("name","pin")))}
	var configured_ids: Array=[]
	for bp in definitions.values():
		if not bp is Dictionary or not bp.get("parts",[]) is Array:continue
		for part in bp.parts:
			if part is Dictionary:configured_ids.append(str(part.get("type","")))
	return preload("res://scripts/electronics/component_values/values.gd").augment(result,configured_ids)
static func validate(id: String,definitions: Dictionary,ancestors: Array=[],budget: Dictionary={}) -> String:
	if budget.is_empty():budget.merge({"parts":0,"nodes":0})
	budget.nodes+=1
	if budget.nodes>128:return "Expanded custom circuit exceeds nesting budget"
	if ancestors.has(id):return "Circular custom IC dependency"
	if ancestors.size()>=8:return "Custom IC nesting limit is eight levels"
	if not definitions.has(id) or not definitions[id] is Dictionary:return "Missing custom IC definition"
	var bp: Dictionary=definitions[id]
	if not bp.get("parts") is Array or not bp.get("wires") is Array or not bp.get("pins") is Array:return "Invalid custom IC"
	if bp.parts.size()>48 or bp.wires.size()>96 or bp.pins.size()<1 or bp.pins.size()>Geometry.MAX_PINS:return "Custom circuit budget: 48 parts, 96 wires, 1–64 pins"
	if bp.get("package","IC") not in ["IC","PCB"]:return "Unknown package type"
	if bp.get("package","IC")=="PCB" or bp.has("footprint"):
		if not bp.get("layout") is Dictionary or not bp.get("footprint") is Dictionary:return "PCB needs layout and footprint"
		if not bp.layout.get("parts") is Array or not bp.layout.get("wires") is Array or bp.layout.parts.size()>48 or bp.layout.wires.size()>96:return "Invalid PCB layout"
		var geometry_error := Geometry.validate(bp)
		if geometry_error!="":return geometry_error
		var layout_error := validate_layout(bp)
		if layout_error!="":return layout_error
	if not bp.get("programs",{}) is Dictionary or bp.get("programs",{}).size()>16:return "Invalid custom circuit programs"
	for program in bp.get("programs",{}).values():
		if not program is Dictionary or not program.get("run",true) is bool:return "Invalid custom circuit firmware"
		if not preload("res://scripts/inventory_authority/firmware_schema.gd").part(program):return "Invalid device source or compiled image"
		if not preload("res://scripts/firmware_runtime.gd").compile(str(program.get("firmware",""))).ok:return "Invalid custom circuit firmware"
	if not bp.get("exposed",[]) is Array:return "Invalid exposed component list"
	for visible_id in bp.get("exposed",[]):
		if not visible_id is String or not bp.parts.any(func(part):return part is Dictionary and str(part.get("id",""))==visible_id):return "Exposed component does not exist"
	var builtin_catalog: Dictionary=preload("res://scripts/electronics/component_values/values.gd").augment(Catalog.all(),bp.parts.map(func(part):return str(part.get("type","")) if part is Dictionary else ""))
	var names := {};var ids := {};var chain := ancestors.duplicate();chain.append(id)
	for pin in bp.pins:
		if not pin is Dictionary or str(pin.get("name","")).is_empty() or str(pin.get("node","")).is_empty() or names.has(str(pin.name)):return "Pins need unique names and assigned nodes"
		names[str(pin.name)]=true
	if bp.get("pin_grid") == "terminal_pitch":
		var used := {}
		for index in bp.pins.size():
			var pin: Dictionary = bp.pins[index]
			var hole := str(pin.get("source_hole",""))
			var rows := int(bp.get("layout",{}).get("rows",0))
			if not layout_hole(hole,rows,bool(bp.get("layout",{}).get("expanded",false))) or used.has(hole) or Geometry.electrical_node(hole,rows) != pin.node:
				return "An external pin does not match its saved source hole."
			if pin.get("number") != index+1 or pin.get("id") != "pin_%d" % (index+1): return "Invalid physical pin numbering."
			used[hole] = true
	for part in bp.parts:
		if not part is Dictionary or ids.has(str(part.get("id",""))) or str(part.get("id","")).is_empty():return "Invalid internal component identity"
		if not preload("res://scripts/inventory_authority/firmware_schema.gd").part(part):return "Invalid component firmware"
		if part.has("surface_rotation") and (not (part.surface_rotation is int or part.surface_rotation is float) or not is_finite(float(part.surface_rotation))):return "Invalid packaged surface rotation"
		ids[str(part.id)]=true
		var type := str(part.get("type",""))
		if type.begins_with("ic:"):
			var error := validate(type,definitions,chain,budget)
			if error!="":return error
			if not part.get("nodes") is Array or part.nodes.size()!=definitions[type].pins.size():return "Custom IC pin count mismatch"
		else:
			if not builtin_catalog.has(type):return "Unsupported internal component"
			if not part.get("nodes",[part.get("a",""),part.get("b","")]) is Array:return "Invalid internal pin list"
			if part.get("nodes",[part.get("a",""),part.get("b","")]).size()!=builtin_catalog[type].pins.size():return "Internal pin count mismatch"
			budget.parts+=preload("res://scripts/device_models.gd").expand(builtin_catalog.get(type,{"kind":"R"}),str(part.id),part.get("nodes",[part.get("a",""),part.get("b","")]),part).size()
			if budget.parts>64:return "Expanded custom circuit exceeds 64 components"
			if not builtin_catalog.has(type) or str(part.get("a","")).is_empty() or str(part.get("b","")).is_empty():return "Unsupported internal component"
	for wire in bp.wires:
		if not wire is Array or wire.size()!=2 or str(wire[0]).is_empty() or str(wire[1]).is_empty():return "Invalid internal connection"
	# Kept independent of BreadboardModel to avoid a preload cycle.
	if not bp.get("io_controls",{}) is Dictionary or bp.get("io_controls",{}).size()>64:return "Invalid packaged I/O controls"
	for input_id in bp.get("io_controls",{}):
		var control=bp.io_controls[input_id]
		if not input_id is String or not control is Dictionary or control.size()>8:return "Invalid packaged I/O input"
		for key in control:
			if key not in ["revision","detent","keys","x","y","pressed","position"]:return "Unknown packaged I/O field"
			if key=="pressed":
				if not control[key] is bool:return "Invalid packaged I/O switch"
			elif not (control[key] is int or control[key] is float) or not is_finite(float(control[key])):return "Invalid packaged I/O number"
	var surface_error := Surface.validate(bp,definitions)
	if not surface_error.is_empty(): return surface_error
	var pcb_error := PCB.validate(bp)
	if pcb_error!="":return pcb_error
	if ResourceLoader.exists("res://scripts/io_devices/host_adapter.gd"):
		var adapter=load("res://scripts/io_devices/host_adapter.gd")
		var io_error: String=adapter.validate_controls(bp.get("io_controls",{}),adapter.kinds(bp.parts,definitions,""))
		if io_error!="":return io_error
	return ""
static func flatten(id: String,definitions: Dictionary,prefix: String,nodes: Array,voltages: Dictionary={},runtime: Dictionary={}) -> Dictionary:
	var result := {"parts":[],"wires":[]}
	var bp: Dictionary=definitions[id]
	if PCB.active(bp):
		# Change only terminal topology. Device IDs, program paths and runtime are unchanged.
		var connection: Dictionary=PCB.connectivity(bp)
		var source_bp: Dictionary=bp
		bp=bp.duplicate()
		bp.wires=[]
		bp.parts=[]
		for source_part in source_bp.parts:
			var part: Dictionary=source_part.duplicate()
			bp.parts.append(part)
			var old_nodes: Array=part.get("nodes",[part.get("a",""),part.get("b","")])
			part.nodes=[]
			for i in old_nodes.size():part.nodes.append(connection[PCB.pad_id(str(part.id),i)])
			part.a=part.nodes[0]
			part.b=part.nodes[mini(1,part.nodes.size()-1)]
		bp.pins=[]
		for i in source_bp.pins.size():
			var pin: Dictionary=source_bp.pins[i].duplicate()
			pin.node=connection[PCB.external_id(pin,i)]
			bp.pins.append(pin)
	runtime=runtime.duplicate();runtime["__programs"]=runtime.get("__programs",{}).duplicate()
	for key in bp.get("programs",{}):
		if not runtime["__programs"].has(prefix+str(key)):runtime["__programs"][prefix+str(key)]=bp.programs[key]
	runtime["__inputs"]=runtime.get("__inputs",{}).duplicate(true)
	for key in bp.get("io_controls",{}):
		if not runtime["__inputs"].has(prefix+str(key)):runtime["__inputs"][prefix+str(key)]=bp.io_controls[key].duplicate(true)
	for index in bp.pins.size():result.wires.append([nodes[index],prefix+str(bp.pins[index].node)])
	for wire in bp.wires:result.wires.append([prefix+str(wire[0]),prefix+str(wire[1])])
	for part in bp.parts:
		if str(part.type).begins_with("ic:"):
			var child := flatten(part.type,definitions,prefix+str(part.id)+"/",part.nodes.map(func(n):return prefix+str(n)),voltages,runtime)
			result.parts.append_array(child.parts);result.wires.append_array(child.wires)
		else:
			var nodes_in: Array=part.get("nodes",[part.get("a",""),part.get("b","")])
			result.parts.append_array(preload("res://scripts/device_models.gd").expand(Catalog.simulation_entry(str(part.type)),prefix+str(part.id),nodes_in.map(func(n):return prefix+str(n)),part,voltages,runtime))
	return result
static func materials(id: String,definitions: Dictionary) -> Dictionary:
	var result := {}
	if validate(id,definitions)!="":return result
	for part in definitions[id].parts:
		var counts: Dictionary=materials(part.type,definitions) if str(part.type).begins_with("ic:") else {part.type:1}
		for type in counts:result[type]=int(result.get(type,0))+int(counts[type])
	return result
static func price(id: String,definitions: Dictionary) -> int:
	var amount := 0;var counts := materials(id,definitions)
	for type in counts:amount+=int(Catalog.simulation_entry(str(type)).get("price",0))*int(counts[type])
	return amount

static func layout_hole(value: Variant,rows: int,expanded := false) -> bool:
	if not value is String or value.length()<2 or not value.substr(1).is_valid_int():return false
	if not expanded and value.left(1) not in Geometry.LEGACY_ROWS+"WX":return false
	return not Geometry.electrical_node(value,rows).is_empty()
static func validate_layout(bp: Dictionary) -> String:
	var layout: Dictionary=bp.layout
	var rows := int(layout.get("rows",0))
	var expanded := bool(layout.get("expanded",false))
	if rows not in [10,20,30,40] or layout.parts.size()!=bp.parts.size():return "Invalid PCB layout size"
	var identities := {}
	for part in bp.parts:
		if not part is Dictionary:return "Invalid PCB component"
		identities[str(part.get("id",""))]=str(part.get("type",""))
	var seen := {}
	for part in layout.parts:
		if not part is Dictionary:return "Invalid PCB layout component"
		var id := str(part.get("id",""))
		if seen.has(id) or not identities.has(id) or identities[id]!=str(part.get("type","")):return "PCB layout does not match its circuit"
		seen[id]=true
		if not layout_hole(part.get("a"),rows,expanded) or not layout_hole(part.get("b"),rows,expanded):return "Invalid PCB component position"
		var pins=part.get("pins",[part.a,part.b])
		if not pins is Array:return "Invalid PCB pin positions"
		for pin in pins:
			if not layout_hole(pin,rows,expanded):return "Invalid PCB pin position"
	for wire in layout.wires:
		if not wire is Array or wire.size()!=2:return "Invalid PCB trace"
		if not layout_hole(wire[0],rows,expanded) or not layout_hole(wire[1],rows,expanded):return "Invalid PCB trace position"
	return ""
