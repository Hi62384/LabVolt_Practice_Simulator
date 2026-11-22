extends RefCounted
## Small, bounded electromechanical assemblies. All prices and references are
## derived from trusted catalogs; clients never submit a cost or a world mesh.
const Custom=preload("res://scripts/custom_circuit.gd")
const Copper=preload("res://scripts/pcb_design/design.gd")
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
const HINGE_OPEN := PI * 65.0 / 180.0
const HINGE_SPEED := PI
const GRID_NEIGHBORS := [Vector3i.RIGHT,Vector3i.LEFT,Vector3i.UP,Vector3i.DOWN,Vector3i.FORWARD,Vector3i.BACK]

## The hinge's forward face carries the moving assembly. Its back face mounts
## to the frame or servo. A servo under the pivot can also drive the joint.
## A frame that wraps around the hinge constrains both sides and locks it.
static func hinges(parts: Array) -> Array[Dictionary]:
	var cells := {}
	var result: Array[Dictionary] = []
	var used := {}
	for i in parts.size():
		if parts[i].type!="hinge":cells[_cell(parts[i])]=i
	for part_index in parts.size():
		var part: Dictionary=parts[part_index]
		if part.type!="hinge":continue
		var pivot := _cell(part)
		var forward := rotate_grid(Vector3i.FORWARD,int(part.get("turns",0)))
		var anchor := pivot-forward
		var moving := pivot+forward
		if not cells.has(anchor) or not cells.has(moving):continue
		var queue: Array[Vector3i] = [moving]
		var visited := {moving:true}
		var cursor := 0
		while cursor<queue.size():
			var cell := queue[cursor]
			cursor+=1
			for direction: Vector3i in GRID_NEIGHBORS:
				var neighbor := cell+direction
				if cells.has(neighbor) and not visited.has(neighbor):
					visited[neighbor]=true
					queue.append(neighbor)
		if visited.has(anchor) or queue.any(func(cell):return used.has(cell)):continue
		var control := ""
		for mount in [anchor,pivot+Vector3i.DOWN]:
			if not cells.has(mount) or visited.has(mount):continue
			var driver: Dictionary=parts[cells[mount]]
			if driver.type=="servo" and posmod(int(driver.get("turns",0))-int(part.get("turns",0)),2)==0:
				control=str(driver.control)
				break
		var indices: Array[int]=[]
		for cell in queue:
			used[cell]=true
			indices.append(cells[cell])
		result.append({"pivot":center(part),"indices":indices,"control":control,"part_index":part_index,"anchor_index":cells[anchor]})
	var carriers := {}
	for index in result.size():
		for member in result[index].indices:carriers[member]=index
	for index in result.size():
		var chain: Array[int]=[index]
		var parent: int=carriers.get(result[index].anchor_index,-1)
		while parent>=0 and parent not in chain:
			chain.push_front(parent)
			parent=carriers.get(result[parent].anchor_index,-1)
		# A closed linkage cannot use independent hinge angles.
		result[index].chain=chain if parent<0 else []
	return result

static func _cell(part: Dictionary) -> Vector3i:
	return Vector3i(part.x,part.y,part.z)

static func center(part: Dictionary) -> Vector3:
	return Vector3(_cell(part))*.3+Vector3.UP*.14

static func hinge_transform(rest: Transform3D,pivot: Vector3,angle: float) -> Transform3D:
	var yaw:=Basis(Vector3.UP,angle)
	return Transform3D(yaw*rest.basis,pivot+yaw*(rest.origin-pivot))

static func hinge_pose(joints: Array,chain: Array,changed: int=-1,angle: float=0.0) -> Transform3D:
	var pose:=Transform3D.IDENTITY
	for index in chain:
		var joint: Dictionary=joints[index]
		pose=pose*hinge_transform(Transform3D.IDENTITY,joint.pivot,angle if index==changed else float(joint.angle))
	return pose

static func hinge_angle(previous: float,control: String,channels: Dictionary,battery: bool,delta: float) -> float:
	return move_toward(previous,HINGE_OPEN if battery and channels.get(control,false) else 0.0,HINGE_SPEED*delta)

## A wheel and motor must have parallel shafts and occupy adjacent cells
## along the shaft axis.
static func connect_wheels(parts: Array) -> void:
	for wheel in parts:
		if wheel.type!="wheel":continue
		wheel.erase("motor_control")
		var turns:=int(wheel.get("turns",0))
		var shaft:=rotate_grid(Vector3i.RIGHT,turns)
		for motor in parts:
			if motor.type!="dc_motor":continue
			if (turns-int(motor.get("turns",0)))%2!=0:continue
			var offset:=Vector3i(wheel.x-motor.x,wheel.y-motor.y,wheel.z-motor.z)
			if offset==shaft or offset==-shaft:
				wheel["motor_control"]=motor.control
				break

static func rotate_grid(point: Vector3i,turns: int) -> Vector3i:
	match posmod(turns,4):
		1:return Vector3i(point.z,point.y,-point.x)
		2:return Vector3i(-point.x,point.y,-point.z)
		3:return Vector3i(-point.z,point.y,point.x)
	return point

## Sum the powered wheels' requested travel vectors. One wheel must not
## arbitrarily overrule a second motor trying to drive the opposite way.
static func wheel_drive(parts: Array,channels: Dictionary,battery: bool) -> Vector3:
	if not battery:return Vector3.ZERO
	var direction:=Vector3.ZERO
	for part in parts:
		if part.get("type","")!="wheel":continue
		var channel: String=str(part.get("motor_control",""))
		if channel.is_empty() or not bool(channels.get(channel,false)):continue
		direction+=Vector3(rotate_grid(Vector3i.FORWARD,int(part.get("turns",0))))
	return direction.normalized() if direction.length_squared()>0.0 else Vector3.ZERO

static func energized(drive: String, switch_on: bool, voltage: float) -> bool:
	if drive=="manual":return switch_on
	if drive=="pcb":return voltage>=2.5
	return switch_on and voltage>=2.5

static func empty(name: String="New invention") -> Dictionary:
	return {"name":name,"parts":[{"type":"wood_frame","x":0,"y":0,"z":0,"control":"","ref":""}],"controls":{"A":"hold","B":"toggle"},"drive":{"A":"manual","B":"manual"}}

# The external supply must not be shorted by assigning different physical
# connectors to the SAME electrical net. On a routed PCB compare actual copper
# topology; schematic labels alone are not conductive until routed.
static func validate_pcb_pin_map(bp: Dictionary,mapping: Variant) -> String:
	if not mapping is Dictionary or mapping.size()!=4:return "Configure PCB supply and output pins"
	var pins: Array=bp.get("pins",[])
	for role in ["power","ground","A","B"]:
		var raw: Variant=mapping.get(role)
		if not (raw is int or raw is float) or not is_finite(float(raw)) or float(raw)!=floor(float(raw)):
			return "Invalid PCB pin mapping"
		if int(raw)<(-1 if role in ["A","B"] else 0) or int(raw)>=pins.size():return "Invalid PCB pin mapping"
	var power:=int(mapping.power)
	var ground:=int(mapping.ground)
	if power==ground:return "PCB power and ground must use different pins"
	var power_net: String
	var ground_net: String
	if Copper.active(bp):
		var routed: Dictionary=Copper.connectivity(bp)
		power_net=str(routed.get(Copper.external_id(pins[power],power),""))
		ground_net=str(routed.get(Copper.external_id(pins[ground],ground),""))
	else:
		# Non-routed PCBs still contain ideal internal jumper wires.
		# Compare joined electrical nodes, not just the external pin labels;
		# different labels may be directly shorted by a saved wire.
		var intended: Dictionary=Copper.intent(bp)
		power_net=str(intended.get(Copper.external_id(pins[power],power),""))
		ground_net=str(intended.get(Copper.external_id(pins[ground],ground),""))
	if not power_net.is_empty() and power_net==ground_net:
		return "PCB power and ground must use different electrical nets"
	return ""

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
		var turns: Variant=part.get("turns",0)
		if not (turns is int or turns is float) or not is_finite(float(turns)) or float(turns)!=floor(float(turns)) or turns<0 or turns>3:
			return "Part rotation must be 0°, 90°, 180° or 270°"
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
				var mapping_error:=validate_pcb_pin_map(pcbs[ref],part.pin_map)
				if not mapping_error.is_empty():return mapping_error
			if kind=="nested":
				var error:=validate(ref,designs,pcbs,depth+1,next_stack)
				if error!="":return error
		elif str(part.get("ref",""))!="":return "Unexpected part reference"
	# First enforce the physical expansion bound, then inspect the *combined*
	# assembly. A parent actuator can use the battery/switch of a nested module,
	# just as the host runtime does after flattening.
	var expanded: Dictionary={}
	var error:=_expanded_check(id,designs,Vector3i.ZERO,0,expanded)
	if error!="":return error
	var expanded_parts: Array=[]
	_flatten(id,designs,Vector3i.ZERO,0,expanded_parts)
	has_frame=false
	has_battery=false
	switches.clear()
	actuators.clear()
	for member in expanded_parts:
		var kind: String=str(member.type)
		if kind in ["wood_frame","aluminum_frame","plastic_shell"]:has_frame=true
		elif kind=="battery":has_battery=true
		elif kind=="switch":switches[str(member.control)]=true
		elif kind in ["dc_motor","servo"]:actuators[str(member.control)]=true
	if not has_frame:return "Add a structural frame or shell"
	if not actuators.is_empty() and not has_battery:return "Add a battery pack to power the moving parts"
	for control in actuators:
		if drive[control] in ["manual","both"] and not switches.has(control):return "Add a control switch for "+str(control)
	if depth==0 and (drive.A in ["pcb","both"] or drive.B in ["pcb","both"]):
		var mapped_pcbs: Array=expanded_parts.filter(func(part):return part.type=="pcb" and part.has("pin_map"))
		if mapped_pcbs.size()!=1:return "Choose exactly one PCB with mapped pins for PCB drive"
		for control in ["A","B"]:
			if drive[control] in ["pcb","both"] and int(mapped_pcbs[0].pin_map[control])<0:return "Map PCB output "+control
	return ""

static func _expanded_check(id: String,designs: Dictionary,offset: Vector3i,turns: int,occupied: Dictionary) -> String:
	for part in designs[id].parts:
		var point:=offset+rotate_grid(Vector3i(part.x,part.y,part.z),turns)
		if part.type=="nested":
			var nested_error:=_expanded_check(str(part.ref),designs,point,turns+int(part.get("turns",0)),occupied)
			if nested_error!="":return nested_error
		else:
			if absi(point.x)>6 or point.y<0 or point.y>6 or absi(point.z)>6:return "Expanded invention exceeds the 0.3 m assembly grid"
			var key: String="%d:%d:%d"%[point.x,point.y,point.z]
			if occupied.has(key):return "Nested parts overlap in the assembly"
			occupied[key]=true
			if occupied.size()>MAX_EXPANDED_PARTS:return "Invention exceeds 64 physical parts"
	return ""

## Once an invention is fabricated, its complete nested blueprint dependency
## graph becomes immutable. Otherwise editing an unfabricated child silently
## changes a parent whose physical copies have already been purchased.
static func fabricated_dependencies(designs: Dictionary,copies: Dictionary) -> Dictionary:
	var frozen: Dictionary={}
	for root in copies:
		if int(copies[root])<=0:continue
		var pending: Array=[str(root)]
		while not pending.is_empty():
			var id: String=str(pending.pop_back())
			if frozen.has(id) or not designs.has(id):continue
			frozen[id]=true
			for part in designs[id].get("parts",[]):
				if part is Dictionary and part.get("type","")=="nested":
					pending.append(str(part.get("ref","")))
	return frozen

## New constructions require real physical adjacency. Keep validate() tolerant
## of older saved profiles so that upgrades do not make legacy saves unreadable.
## Fabrication, placement and the editor call this stricter contract.
static func structure_error(id: String,designs: Dictionary,pcbs: Dictionary) -> String:
	var error:=validate(id,designs,pcbs)
	if not error.is_empty():return error
	var parts:=flattened(id,designs,pcbs)
	if parts.is_empty():return "The assembly has no physical parts"
	var occupied: Dictionary={}
	var origin: Vector3i=Vector3i.ZERO
	for part in parts:
		var cell:=_cell(part)
		occupied[cell]=true
		if part.type in ["wood_frame","aluminum_frame","plastic_shell"]:origin=cell
	var visited: Dictionary={origin:true}
	var queue: Array[Vector3i]=[origin]
	var cursor:=0
	while cursor<queue.size():
		var cell: Vector3i=queue[cursor]
		cursor+=1
		for offset in GRID_NEIGHBORS:
			var neighbor: Vector3i=cell+offset
			if occupied.has(neighbor) and not visited.has(neighbor):
				visited[neighbor]=true
				queue.append(neighbor)
	if visited.size()!=parts.size():return "Connect all parts to a frame with adjacent grid cells; floating components cannot be fabricated."
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
	_flatten(id,designs,Vector3i.ZERO,0,result)
	return result

static func _flatten(id: String,designs: Dictionary,offset: Vector3i,turns: int,result: Array) -> void:
	for part in designs[id].parts:
		var point:=offset+rotate_grid(Vector3i(part.x,part.y,part.z),turns)
		var part_turns:=posmod(turns+int(part.get("turns",0)),4)
		if part.type=="nested":_flatten(str(part.ref),designs,point,part_turns,result)
		else:
			var copy: Dictionary=part.duplicate(true)
			copy.x=point.x;copy.y=point.y;copy.z=point.z
			if part_turns!=0:copy.turns=part_turns
			else:copy.erase("turns")
			result.append(copy)
