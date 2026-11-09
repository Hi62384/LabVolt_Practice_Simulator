extends RefCounted
const Design=preload("res://scripts/pcb_design/design.gd")
var blueprint: Dictionary={}
var undo_stack: Array=[]
var redo_stack: Array=[]
var error := ""
func open(value: Dictionary) -> void:
	blueprint=Design.migrate(value)
	undo_stack.clear();redo_stack.clear();error=Design.validate(blueprint)
func commit(candidate: Dictionary) -> bool:
	error=Design.validate(candidate)
	if error!="":return false
	undo_stack.append(blueprint.duplicate(true))
	if undo_stack.size()>32:undo_stack.pop_front()
	redo_stack.clear();blueprint=candidate.duplicate(true);return true
func set_outline(points: Array) -> bool:
	var candidate:=blueprint.duplicate(true);candidate.pcb_design.outline=points.duplicate(true);return commit(candidate)
func move_pad(id: String,position: Array,whole_component: bool=true) -> bool:
	if not blueprint.pcb_design.pads.has(id):error="Unknown pad";return false
	if not Design.point(position):error="Invalid pad coordinates";return false
	var candidate:=blueprint.duplicate(true)
	var delta:=Design.v(position)-Design.v(candidate.pcb_design.pads[id].position)
	var group:=id.substr(0,id.rfind(":")) if id.begins_with("p:") and whole_component else id
	var moved: Array=[]
	for key in candidate.pcb_design.pads:
		if key==id or (whole_component and id.begins_with("p:") and str(key).begins_with(group+":")):
			var p:=Design.v(candidate.pcb_design.pads[key].position)+delta
			candidate.pcb_design.pads[key].position=[p.x,p.y];moved.append(key)
	for route in candidate.pcb_design.routes:
		if route.a in moved:route.points[0]=candidate.pcb_design.pads[route.a].position.duplicate()
		if route.b in moved:route.points[-1]=candidate.pcb_design.pads[route.b].position.duplicate()
	return commit(candidate)
func add_route(a: String,b: String,points: Array,width: float=.06) -> bool:
	var candidate:=blueprint.duplicate(true)
	candidate.pcb_design.routes.append({"id":"trace_"+str(Time.get_ticks_usec()),"a":a,"b":b,"points":points.duplicate(true),"width":width})
	return commit(candidate)
func remove_route(index: int) -> bool:
	if index<0 or index>=blueprint.pcb_design.routes.size():return false
	var candidate:=blueprint.duplicate(true);candidate.pcb_design.routes.remove_at(index);return commit(candidate)
func undo() -> bool:
	if undo_stack.is_empty():return false
	redo_stack.append(blueprint.duplicate(true));blueprint=undo_stack.pop_back();error="";return true
func redo() -> bool:
	if redo_stack.is_empty():return false
	undo_stack.append(blueprint.duplicate(true));blueprint=redo_stack.pop_back();error="";return true
func save_copy(profile: RefCounted) -> String:
	if not profile.data.get("pending_trade",{}).is_empty():return "Finish the pending trade first"
	error=Design.validate(blueprint)
	if error!="":return error
	var bp:=blueprint.duplicate(true)
	bp.revision=int(bp.get("revision",1))+1
	var id:="ic:"+JSON.stringify(bp).sha256_text().left(24)
	var definitions: Dictionary=profile.data.get("blueprints",{}).duplicate(true);definitions[id]=bp
	error=preload("res://scripts/custom_circuit.gd").validate(id,definitions)
	if error!="":return error
	var before: Dictionary=profile.data.duplicate(true)
	profile.data.blueprints=definitions
	if profile.save()!=OK:profile.data=before;return "Save failed; original definitions unchanged"
	return "Blueprint saved: "+id

func resize(width: int,height: int,thickness: float) -> bool:
	if width<2 or width>80 or height<2 or height>80 or not is_finite(thickness) or thickness<.1 or thickness>100:error="Package extent/thickness outside supported limits";return false
	var candidate:=blueprint.duplicate(true)
	candidate.footprint.width=width;candidate.footprint.height=height;candidate.footprint.thickness_mm=thickness
	return commit(candidate)

func rotate_component(id: String) -> bool:
	var candidate:=blueprint.duplicate(true)
	var group:="p:"+id+":"
	var keys: Array=[]
	var low:=Vector2(INF,INF);var high:=Vector2(-INF,-INF)
	for key in candidate.pcb_design.pads:
		if str(key).begins_with(group):
			keys.append(key)
			var p:=Design.v(candidate.pcb_design.pads[key].position);low=low.min(p);high=high.max(p)
	if keys.is_empty():error="Select a component pad to rotate";return false
	var center:=(low+high)*.5
	for key in keys:
		var delta:=Design.v(candidate.pcb_design.pads[key].position)-center
		var p:=center+Vector2(-delta.y,delta.x)
		candidate.pcb_design.pads[key].position=[p.x,p.y]
	for route in candidate.pcb_design.routes:
		if route.a in keys:route.points[0]=candidate.pcb_design.pads[route.a].position.duplicate()
		if route.b in keys:route.points[-1]=candidate.pcb_design.pads[route.b].position.duplicate()
	for collection in [candidate.parts,candidate.layout.parts]:
		for part in collection:
			if str(part.id)==id:part.surface_rotation=float(part.get("surface_rotation",0))+PI/2
	return commit(candidate)
