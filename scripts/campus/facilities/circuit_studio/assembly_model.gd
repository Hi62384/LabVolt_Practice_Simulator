extends RefCounted
## Small, bounded electromechanical assemblies. All prices and references are
## derived from trusted catalogs; clients never submit a cost or a world mesh.
const Custom=preload("res://scripts/custom_circuit.gd")
const PARTS={
	"wood_frame":{"name":"Wood frame","group":"Material","price":8,"color":"a47b51"},
	"aluminum_frame":{"name":"Aluminum frame","group":"Material","price":18,"color":"aabec7"},
	"plastic_shell":{"name":"Plastic shell","group":"Material","price":6,"color":"4b8d9f"},
	"wheel":{"name":"Wheel","group":"Mechanical","price":12,"color":"27343c"},
	"hinge":{"name":"Hinge","group":"Mechanical","price":10,"color":"b5a88b"},
	"dc_motor":{"name":"DC motor","group":"Electrical / mechanical","price":24,"color":"738c9b"},
	"servo":{"name":"Servo","group":"Electrical / mechanical","price":32,"color":"536f83"},
	"battery":{"name":"Battery pack","group":"Electrical","price":16,"color":"b79c4b"},
	"switch":{"name":"Control switch","group":"Electrical","price":5,"color":"d6a765"},
	"pcb":{"name":"Custom PCB","group":"Electrical","price":0,"color":"348a6b"},
	"nested":{"name":"Nested design","group":"Assembly","price":0,"color":"9c85b1"},
}
const MAX_PARTS:=32
const MAX_DEPTH:=4
const MAX_EXPANDED_PARTS:=64

static func empty(name: String="New invention") -> Dictionary:
	return {"name":name,"parts":[{"type":"wood_frame","x":0,"y":0,"z":0,"control":"","ref":""}],"controls":{"A":"hold","B":"toggle"},"drive":{"A":"manual","B":"manual"}}

static func validate(id: String,designs: Dictionary,pcbs: Dictionary,depth: int=0,stack: Array=[]) -> String:
	if depth>MAX_DEPTH or id in stack:return "Nested design limit or cycle"
	if not designs.has(id) or not designs[id] is Dictionary:return "Unknown invention"
	var design: Dictionary=designs[id]
	if not design.get("name") is String or str(design.name).strip_edges().is_empty() or str(design.name).length()>40:return "Invalid invention name"
	if not design.get("parts") is Array or design.parts.is_empty() or design.parts.size()>MAX_PARTS:return "Invention needs 1–32 parts"
	var controls: Variant=design.get("controls",{})
	if not controls is Dictionary or controls.size()!=2 or controls.get("A") not in ["hold","toggle"] or controls.get("B") not in ["hold","toggle"]:return "Invalid control modes"
	var drive: Variant=design.get("drive",{"A":"manual","B":"manual"})
	if not drive is Dictionary or drive.size()!=2 or drive.get("A") not in ["manual","pcb","both"] or drive.get("B") not in ["manual","pcb","both"]:return "Invalid drive source"
	var occupied: Dictionary={}
	var has_frame:=false
	var has_battery:=false
	var switches: Dictionary={}
	var actuators: Dictionary={}
	var next_stack:=stack.duplicate();next_stack.append(id)
	for part in design.parts:
		if not part is Dictionary or not PARTS.has(part.get("type","")):return "Unknown assembly part"
		for axis in ["x","y","z"]:
			var value: Variant=part.get(axis)
			if not (value is int or value is float) or not is_finite(float(value)) or float(value)!=floor(float(value)) or absi(int(value))>6 or (axis=="y" and int(value)<0):return "Part position is outside the assembly grid"
		var key: String="%d:%d:%d"%[part.x,part.y,part.z]
		if occupied.has(key):return "Two parts occupy the same grid cell"
		occupied[key]=true
		var kind: String=part.type
		if kind in ["wood_frame","aluminum_frame","plastic_shell"]:has_frame=true
		if kind=="battery":has_battery=true
		var control: Variant=part.get("control","")
		if not control is String or control not in ["","A","B"]:return "Invalid part control"
		if kind in ["dc_motor","servo"] and control=="":return "Assign each motor a control"
		if kind=="switch" and control=="":return "Assign each switch a control"
		if kind=="switch":switches[control]=true
		if kind in ["dc_motor","servo"]:actuators[control]=true
		if kind in ["pcb","nested"]:
			var ref: Variant=part.get("ref","")
			if not ref is String:return "Invalid part reference"
			if kind=="pcb" and (not pcbs.has(ref) or Custom.validate(ref,pcbs)!="" or str(pcbs[ref].get("package",""))!="PCB"):return "Choose a saved PCB blueprint"
			if kind=="pcb" and part.has("pin_map"):
				var map: Variant=part.pin_map
				if not map is Dictionary or map.size()!=4:return "Configure PCB supply and output pins"
				for pin in ["power","ground","A","B"]:
					var index: Variant=map.get(pin)
					if not (index is int or index is float) or not is_finite(float(index)) or float(index)!=floor(float(index)) or int(index)<(-1 if pin in ["A","B"] else 0) or int(index)>=pcbs[ref].pins.size():return "Invalid PCB pin mapping"
				if int(map.power)==int(map.ground):return "PCB power and ground must use different pins"
			if kind=="nested":
				var error:=validate(ref,designs,pcbs,depth+1,next_stack)
				if error!="":return error
		elif str(part.get("ref",""))!="":return "Unexpected part reference"
	if not has_frame:return "Add a structural frame or shell"
	if not actuators.is_empty() and not has_battery:return "Add a battery pack to power the moving parts"
	for control in actuators:
		if drive[control] in ["manual","both"] and not switches.has(control):return "Add a control switch for "+str(control)
	if depth==0:
		var expanded: Dictionary={}
		var error:=_expanded_check(id,designs,Vector3i.ZERO,expanded)
		if error!="":return error
		if drive.A in ["pcb","both"] or drive.B in ["pcb","both"]:
			var expanded_parts: Array=[]
			_flatten(id,designs,Vector3i.ZERO,expanded_parts)
			var mapped_pcbs: Array=expanded_parts.filter(func(part):return part.type=="pcb" and part.has("pin_map"))
			if mapped_pcbs.size()!=1:return "Choose exactly one PCB with mapped pins for PCB drive"
			for control in ["A","B"]:
				if drive[control] in ["pcb","both"] and int(mapped_pcbs[0].pin_map[control])<0:return "Map PCB output "+control
	return ""

static func _expanded_check(id: String,designs: Dictionary,offset: Vector3i,occupied: Dictionary) -> String:
	for part in designs[id].parts:
		var point:=offset+Vector3i(int(part.x),int(part.y),int(part.z))
		if part.type=="nested":
			var nested_error:=_expanded_check(str(part.ref),designs,point,occupied)
			if nested_error!="":return nested_error
		else:
			if absi(point.x)>6 or point.y<0 or point.y>6 or absi(point.z)>6:return "Expanded invention exceeds the 0.3 m assembly grid"
			var key: String="%d:%d:%d"%[point.x,point.y,point.z]
			if occupied.has(key):return "Nested parts overlap in the assembly"
			occupied[key]=true
			if occupied.size()>MAX_EXPANDED_PARTS:return "Invention exceeds 64 physical parts"
	return ""

static func price(id: String,designs: Dictionary,pcbs: Dictionary) -> int:
	if validate(id,designs,pcbs)!="":return -1
	return _price(id,designs,pcbs)

static func _price(id: String,designs: Dictionary,pcbs: Dictionary) -> int:
	var total:=0
	for part in designs[id].parts:
		match str(part.type):
			"nested":total+=_price(str(part.ref),designs,pcbs)
			"pcb":total+=Custom.price(str(part.ref),pcbs)
			_:total+=int(PARTS[part.type].price)
	return total

static func flattened(id: String,designs: Dictionary,pcbs: Dictionary) -> Array:
	if validate(id,designs,pcbs)!="":return []
	var result: Array=[]
	_flatten(id,designs,Vector3i.ZERO,result)
	return result

static func _flatten(id: String,designs: Dictionary,offset: Vector3i,result: Array) -> void:
	for part in designs[id].parts:
		var point:=offset+Vector3i(part.x,part.y,part.z)
		if part.type=="nested":_flatten(str(part.ref),designs,point,result)
		else:
			var copy: Dictionary=part.duplicate(true)
			copy.x=point.x;copy.y=point.y;copy.z=point.z
			result.append(copy)
