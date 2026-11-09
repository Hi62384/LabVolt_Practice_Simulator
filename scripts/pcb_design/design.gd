extends RefCounted
## Bounded single-plane copper design. Intended nets are DRC labels, not hidden connections.
const MAX_PADS := 512
const MAX_ROUTES := 96
const EPS := .00001
static var topology_cache: Dictionary = {}
static func active(bp: Dictionary) -> bool: return bp.has("pcb_design")
static func point(value: Variant) -> bool:
	return value is Array and value.size()==2 and (value[0] is float or value[0] is int) and (value[1] is float or value[1] is int) and is_finite(float(value[0])) and is_finite(float(value[1]))
static func v(value: Array) -> Vector2: return Vector2(float(value[0]),float(value[1]))
static func polygon(design: Dictionary) -> PackedVector2Array:
	var result := PackedVector2Array()
	for value in design.get("outline",[]): result.append(v(value))
	return result
static func pad_id(part_id: String,index: int) -> String: return "p:"+part_id+":"+str(index)
static func external_id(pin: Dictionary,index: int) -> String: return "x:"+str(pin.get("id","pin_"+str(index+1)))
static func terminal_nodes(bp: Dictionary) -> Dictionary:
	var result := {}
	for part in bp.get("parts",[]):
		var nodes: Array=part.get("nodes",[part.get("a",""),part.get("b","")])
		for i in nodes.size(): result[pad_id(str(part.id),i)]=str(nodes[i])
	for i in bp.get("pins",[]).size(): result[external_id(bp.pins[i],i)]=str(bp.pins[i].node)
	return result
static func root_of(parent: Dictionary,node: String) -> String:
	var current := node
	while parent.has(current) and str(parent[current])!=current: current=str(parent[current])
	return current
static func intent(bp: Dictionary) -> Dictionary:
	var labels := terminal_nodes(bp)
	var parent := {}
	for node in labels.values(): parent[str(node)]=str(node)
	for wire in bp.get("wires",[]):
		if not parent.has(str(wire[0])): parent[str(wire[0])]=str(wire[0])
		if not parent.has(str(wire[1])): parent[str(wire[1])]=str(wire[1])
		parent[root_of(parent,str(wire[1]))]=root_of(parent,str(wire[0]))
	for key in labels: labels[key]=root_of(parent,str(labels[key]))
	return labels
static func segment_distance(a: Vector2,b: Vector2,c: Vector2,d: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a,b,c,d)!=null: return 0.0
	return minf(minf(a.distance_to(Geometry2D.get_closest_point_to_segment(a,c,d)),b.distance_to(Geometry2D.get_closest_point_to_segment(b,c,d))),minf(c.distance_to(Geometry2D.get_closest_point_to_segment(c,a,b)),d.distance_to(Geometry2D.get_closest_point_to_segment(d,a,b))))
static func inside(p: Vector2,poly: PackedVector2Array) -> bool:
	if Geometry2D.is_point_in_polygon(p,poly): return true
	for i in poly.size():
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p,poly[i],poly[(i+1)%poly.size()]))<EPS: return true
	return false
static func segment_inside(a: Vector2,b: Vector2,poly: PackedVector2Array,margin: float) -> bool:
	if not inside(a,poly) or not inside(b,poly): return false
	# A segment through a concave cutout can have both endpoints inside.
	for i in poly.size():
		var c := poly[i];var d := poly[(i+1)%poly.size()]
		if segment_distance(a,b,c,d)<margin-EPS: return false
	return true
# Outline preview can skip unchanged copper-to-copper checks. Authoritative validation
# and every commit use the default FULL path; preview never authorizes a save.
static func validate(bp: Dictionary,outline_preview: bool=false) -> String:
	if not active(bp): return ""
	if bp.get("package","")!="PCB" or not bp.pcb_design is Dictionary: return "Routing requires a PCB"
	var data: Dictionary=bp.pcb_design
	if data.get("version")!=1: return "Unsupported PCB design version"
	if not data.get("outline") is Array or data.outline.size()<3 or data.outline.size()>64: return "Outline needs 3–64 points"
	var width := float(bp.footprint.width)-1
	var height := float(bp.footprint.height)-1
	for value in data.outline:
		if not point(value) or v(value).x<0 or v(value).y<0 or v(value).x>width or v(value).y>height: return "Outline point outside footprint"
	var poly := polygon(data)
	for i in poly.size():
		if poly[i].distance_to(poly[(i+1)%poly.size()])<.02: return "Outline has a zero-length edge"
		for j in range(i+1,poly.size()):
			if j==i+1 or (i==0 and j==poly.size()-1): continue
			if segment_distance(poly[i],poly[(i+1)%poly.size()],poly[j],poly[(j+1)%poly.size()])<EPS: return "Outline self-intersects"
	if Geometry2D.triangulate_polygon(poly).is_empty(): return "Outline has no usable area"
	for key in ["clearance","pad_radius"]:
		var value=data.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value)<.02 or float(value)>.4: return "Clearance/pad radius must be 0.02–0.4 grid units"
	var clearance := float(data.clearance)
	var radius := float(data.pad_radius)
	var labels := intent(bp)
	if not data.get("pads") is Dictionary or data.pads.size()!=labels.size() or labels.size()>MAX_PADS: return "PCB pads must match every component and connector pin"
	var pads: Dictionary=data.pads
	for id in pads:
		if not labels.has(id) or not pads[id] is Dictionary or not point(pads[id].get("position")): return "Invalid PCB pad"
		if str(pads[id].get("net",""))!=labels[id]: return "PCB net labels do not match conversion intent"
		var pos := v(pads[id].position)
		if not inside(pos,poly): return "Pad outside outline"
		for i in poly.size():
			if pos.distance_to(Geometry2D.get_closest_point_to_segment(pos,poly[i],poly[(i+1)%poly.size()]))<radius-EPS: return "Pad too close to outline edge"
	var keys: Array=pads.keys()
	for i in (0 if outline_preview else keys.size()):
		for j in range(i+1,keys.size()):
			var a: Dictionary=pads[keys[i]];var b: Dictionary=pads[keys[j]]
			var limit := radius*2+(clearance if a.net!=b.net else 0.0)
			if v(a.position).distance_to(v(b.position))<limit-EPS: return "Pads overlap or violate clearance"
	if not data.get("routes") is Array or data.routes.size()>MAX_ROUTES: return "PCB route budget exceeded"
	var route_ids := {}
	var segments: Array=[]
	for route in data.routes:
		if not route is Dictionary or not route.get("id") is String or route.id.is_empty() or route.id.length()>64 or route_ids.has(route.id): return "Routes need unique bounded IDs"
		route_ids[route.id]=true
		if not pads.has(route.get("a")) or not pads.has(route.get("b")) or route.a==route.b: return "Route needs two distinct existing pads"
		if pads[route.a].net!=pads[route.b].net: return "Route would short different intended nets"
		var trace_width=route.get("width")
		if not (trace_width is float or trace_width is int) or not is_finite(float(trace_width)) or float(trace_width)<.02 or float(trace_width)>.3: return "Trace width must be 0.02–0.3 grid units"
		if not route.get("points") is Array or route.points.size()<2 or route.points.size()>16: return "Route needs 2–16 points"
		for value in route.points:
			if not point(value): return "Invalid trace point"
		if v(route.points[0]).distance_to(v(pads[route.a].position))>EPS or v(route.points[-1]).distance_to(v(pads[route.b].position))>EPS: return "Trace endpoints must terminate on their pads"
		for i in range(1,route.points.size()):
			var a := v(route.points[i-1]);var b := v(route.points[i])
			if a.distance_to(b)<.02 or not segment_inside(a,b,poly,float(trace_width)/2): return "Trace leaves outline or has zero length"
			var net := str(pads[route.a].net)
			for id in ([] if outline_preview else pads.keys()):
				if str(pads[id].net)!=net and v(pads[id].position).distance_to(Geometry2D.get_closest_point_to_segment(v(pads[id].position),a,b))<radius+float(trace_width)/2+clearance-EPS: return "Trace shorts or approaches an unrelated pad"
			for other in segments:
				if other.net!=net and segment_distance(a,b,other.a,other.b)<(float(trace_width)+float(other.width))/2+clearance-EPS: return "Copper traces short or violate clearance"
			if not outline_preview:segments.append({"a":a,"b":b,"width":trace_width,"net":net})
	return ""
static func connectivity(bp: Dictionary) -> Dictionary:
	var key := hash(bp.pcb_design)
	if topology_cache.has(key) and topology_cache[key].design==bp.pcb_design: return topology_cache[key].result.duplicate()
	var result := _connectivity(bp)
	if topology_cache.size()>=16: topology_cache.erase(topology_cache.keys()[0])
	topology_cache[key]={"design":bp.pcb_design.duplicate(true),"result":result.duplicate()}
	return result
static func _connectivity(bp: Dictionary) -> Dictionary:
	var data: Dictionary=bp.pcb_design
	var parent := {}
	for id in data.pads: parent[id]=id
	for route in data.routes: parent[root_of(parent,route.b)]=root_of(parent,route.a)
	# Copper touching an intermediate pad or crossing same-net copper conducts too.
	for route in data.routes:
		for id in data.pads:
			for i in range(1,route.points.size()):
				if v(data.pads[id].position).distance_to(Geometry2D.get_closest_point_to_segment(v(data.pads[id].position),v(route.points[i-1]),v(route.points[i])))<=float(data.pad_radius)+float(route.width)/2+EPS:
					parent[root_of(parent,id)]=root_of(parent,route.a)
	for i in data.routes.size():
		for j in range(i+1,data.routes.size()):
			var a: Dictionary=data.routes[i];var b: Dictionary=data.routes[j]
			for ai in range(1,a.points.size()):
				for bi in range(1,b.points.size()):
					if segment_distance(v(a.points[ai-1]),v(a.points[ai]),v(b.points[bi-1]),v(b.points[bi]))<=(float(a.width)+float(b.width))/2+EPS: parent[root_of(parent,b.a)]=root_of(parent,a.a)
	var result := {}
	for id in parent: result[id]="pcb:"+root_of(parent,id)
	return result
static func unrouted(bp: Dictionary) -> int:
	var connected := connectivity(bp)
	var groups := {}
	for id in bp.pcb_design.pads:
		var net: String=bp.pcb_design.pads[id].net
		if not groups.has(net): groups[net]={}
		groups[net][connected[id]]=true
	var count := 0
	for group in groups.values(): count+=maxi(0,group.size()-1)
	return count
static func draw_grid(canvas: CanvasItem, rect: Rect2, footprint: Dictionary, outline := PackedVector2Array()) -> void:
	var tint := Color(1,1,1,.13)
	var columns := int(footprint.get("width",0))
	var rows := int(footprint.get("height",0))
	for x in range(1,columns):
		var px := rect.position.x + rect.size.x*x/columns
		_draw_grid_line(canvas,Vector2(px,rect.position.y),Vector2(px,rect.end.y),tint,outline)
	for y in range(1,rows):
		var py := rect.position.y + rect.size.y*y/rows
		_draw_grid_line(canvas,Vector2(rect.position.x,py),Vector2(rect.end.x,py),tint,outline)

static func _draw_grid_line(canvas: CanvasItem, start: Vector2, end: Vector2, tint: Color, outline: PackedVector2Array) -> void:
	if outline.is_empty():
		canvas.draw_line(start,end,tint,1)
		return
	for segment in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([start,end]),outline):
		canvas.draw_polyline(segment,tint,1)

static func map_point(bp: Dictionary,position: Array,rect: Rect2) -> Vector2:
	return rect.position+v(position)/Vector2(float(bp.footprint.width)-1,float(bp.footprint.height)-1)*rect.size
static func migrate(bp: Dictionary) -> Dictionary:
	var copy := bp.duplicate(true)
	if active(copy): return copy
	var width := float(copy.footprint.width)-1;var height := float(copy.footprint.height)-1
	var labels := intent(copy)
	# Increase only the NEW routing copy when distinct lands cannot fit the legacy body.
	var columns := maxi(1,ceili(sqrt(float(labels.size())*width/maxf(1,height))))
	var rows := maxi(1,ceili(float(labels.size())/columns))
	copy.footprint.width=maxi(int(copy.footprint.width),ceili((columns-1)*.32+.6)+1)
	copy.footprint.height=maxi(int(copy.footprint.height),ceili((rows-1)*.32+.6)+1)
	width=float(copy.footprint.width)-1;height=float(copy.footprint.height)-1
	var data := {"version":1,"clearance":.08,"pad_radius":.10,"outline":[[0,0],[width,0],[width,height],[0,height]],"pads":{},"routes":[]}
	var index := 0
	for id in labels:
		var x := .3+(index%columns)*((width-.6)/maxi(1,columns-1))
		var y := .3+(index/columns)*((height-.6)/maxi(1,rows-1))
		data.pads[id]={"position":[x,y],"net":labels[id]}
		index+=1
	copy.pcb_design=data
	return copy
