extends RefCounted
## All inputs come from host state/validated poses. Peer-supplied room, zone,
## owner, session or dependency fields are deliberately ignored.
const Interest = preload("res://scripts/campus/performance/zone_interest.gd")
var radius := 8.0
var doorway_radius := 8.0
var lead_radius := 5.0

func from_game(game: Node, states: Array) -> Dictionary:
	var registry: Object = game.campus.registry if is_instance_valid(game.campus) else null
	var ac_ports: Array = []
	var extra := {}
	for index in game.session.labs.size():
		var lab=game.session.labs[index]
		ac_ports.append(lab.positions)
		for lead in lab.cables:
			if int(lead.get("owner",0))>0:_add(extra,int(lead.owner),game.dc_lab.AC_OFFSET+index)
	for peer in game.dc_lab.pending_endpoints:
		_add(extra,int(peer),int(game.dc_lab.pending_endpoints[peer].station))
	for holder in game.dc_lab.input_holders.values():
		_add(extra,int(holder.peer),int(holder.index))
	for holder in game.dc_lab.held_io.values():
		if holder is Dictionary and holder.has("peer"):
			_add(extra,int(holder.peer),int(holder.get("index",holder.get("station",-1))))
	for lease in game.dc_lab.io_guard.leases.values():
		_add(extra,int(lease.peer),int(lease.station))
	var school := {"identities":game.school.identities,"allocation":game.school.allocation,"activity":game.school.activity}
	return build(game.session.roster,game.session.poses,registry,states,game.dc_lab.ports,ac_ports,game.dc_lab.external_links,school,extra,game.dc_lab.AC_OFFSET)

func build(roster: Dictionary, validated_poses: Dictionary, registry: Object, states: Array, dc_ports: Array, ac_ports: Array, external_links: Array, school: Dictionary = {}, explicit_dependencies: Dictionary = {}, ac_offset := 3) -> Dictionary:
	var rooms: Array[Dictionary] = [_course_room(registry,"ETY155"),_course_room(registry,"ELM253")]
	var all_ports := {}
	for index in dc_ports.size():all_ports[index]=dc_ports[index]
	for index in ac_ports.size():all_ports[ac_offset+index]=ac_ports[index]
	var metas := {}
	for index in all_ports:
		var room := rooms[0] if index<3 else rooms[1] if index>=ac_offset else {}
		var meta := {"zone_id":str(room.get("zone",room.get("id",""))),"room_id":str(room.get("id","")),"building":str(room.get("building","")),"dependencies":[]}
		var anchor: Variant = _anchor(all_ports[index])
		if anchor is Vector3:meta.position=anchor
		if index<states.size():meta.owner=int(states[index].get("board_owner",0))
		if index>=3 and index<states.size() and index<ac_offset:meta.dependency_only=true
		metas[index]=meta
	var graph := {}
	var links: Array = []
	for link in external_links:
		if not link is Dictionary or not link.get("a") is Dictionary or not link.get("b") is Dictionary:continue
		var a := int(link.a.get("station",-1));var b := int(link.b.get("station",-1))
		if not all_ports.has(a) or not all_ports.has(b):continue
		if not graph.has(a):graph[a]=[]
		if not graph.has(b):graph[b]=[]
		graph[a].append(b);graph[b].append(a);links.append(link)
	var peers := {}
	var wanted := {}
	var link_peers: Array = []
	var predicate := Interest.new()
	predicate.distance_limit=radius
	for peer_key in roster:
		var peer := int(peer_key)
		var pose: Dictionary = validated_poses.get(peer,{})
		var context := {"id":peer,"interest_zones":[]}
		if pose.get("position") is Vector3 and pose.position.is_finite():
			context.position=pose.position
			var room_id := str(registry.call("locate",pose.position)) if is_instance_valid(registry) else ""
			var room: Dictionary = registry.call("get_room",room_id) if is_instance_valid(registry) else {}
			context.room_id=room_id;context.zone_id=str(room.get("zone",room_id));context.building=str(room.get("building",""))
			for equipment_room in rooms:
				if room_id in equipment_room.get("neighbors",[]) and equipment_room.get("door") is Array:
					var door := _point(equipment_room.door)
					if door.distance_to(pose.position)<=doorway_radius:
						context.interest_zones.append(str(equipment_room.get("zone",equipment_room.get("id",""))))
		peers[peer]=context
		var seeds: Array = explicit_dependencies.get(peer,[]).duplicate()
		var identity := str(school.get("identities",{}).get(peer,""))
		var slot: Dictionary = school.get("allocation",{}).get(identity,{})
		var activity: Dictionary = school.get("activity",{})
		if activity.get("kind","")=="lab" and slot.has("bench"):
			var course := str(activity.get("course_id",""))
			if course in ["ETY155","ELM253"]:
				seeds.append(int(slot.bench)+(ac_offset if course=="ELM253" else 0))
		for index in metas:
			if not metas[index].get("dependency_only",false) and predicate.is_relevant(context,metas[index]) and index not in seeds:seeds.append(index)
		for index in mini(ac_offset,states.size()):
			var state: Dictionary = states[index]
			if int(state.get("board_owner",0))==peer and (index>=3 or state.get("board_held",false)):
				seeds.append(index)
		if context.get("position") is Vector3:
			for index in states.size():
				var state: Dictionary = states[index]
				if state.get("board", {}).is_empty() or state.get("board_stowed", false):
					continue
				var point: Vector3 = state.get("board_position", Vector3.ZERO)
				if state.get("board_held", false):
					point = validated_poses.get(state.get("board_owner", 0), {}).get("position", Vector3.ZERO)
				if point != Vector3.ZERO and context.position.distance_to(point) <= radius:
					seeds.append(index)
			for link in links:
				var a: Variant = all_ports[int(link.a.station)].get(str(link.a.get("port","")))
				var b: Variant = all_ports[int(link.b.station)].get(str(link.b.get("port","")))
				if a is Vector3 and b is Vector3 and _segment_distance(context.position,a,b)<=lead_radius:
					seeds.append(int(link.a.station));seeds.append(int(link.b.station))
		var closure: Array = []
		for index in seeds:
			if metas.has(int(index)) and int(index) not in closure:closure.append(int(index))
		var cursor := 0
		while cursor<closure.size():
			for linked in graph.get(closure[cursor],[]):
				if linked not in closure:closure.append(linked)
			cursor+=1
		wanted[peer]=closure
		var dc_wanted := false
		for index in closure:
			metas[index].dependencies.append(peer)
			if index<ac_offset:dc_wanted=true
		if dc_wanted:link_peers.append(peer)
	var objects := {}
	for index in mini(ac_offset,states.size()):
		var state: Dictionary = states[index].duplicate()
		state.erase("external_links")
		var meta: Dictionary = metas.get(index,{}).duplicate()
		# The context already resolved room/radius/dependency closure. Do not let a
		# router's generic default radius widen this authoritative wanted set.
		meta.dependency_only=true
		objects["dc/"+str(index)]={"meta":meta,"state":state}
	objects["links"]={"meta":{"dependency_only":true,"dependencies":link_peers},"state":{"external_links":links.duplicate(true)}}
	return {"peers":peers,"objects":objects,"wanted_station_indices":wanted,"ignored_link_count":external_links.size()-links.size()}

func _course_room(registry: Object, course: String) -> Dictionary:
	return registry.call("course_room",course,"lab") if is_instance_valid(registry) else {}

func _point(values: Array) -> Vector3:
	return Vector3(float(values[0]),float(values[1]),float(values[2]))

func _anchor(ports: Dictionary) -> Variant:
	var sum := Vector3.ZERO
	var count := 0
	for key in ports:
		if str(key).begins_with("X") or not ports[key] is Vector3:continue
		sum+=ports[key];count+=1
	return sum/float(count) if count>0 else null

func _segment_distance(point: Vector3, a: Vector3, b: Vector3) -> float:
	var difference := b-a
	var weight := clampf((point-a).dot(difference)/difference.length_squared(),0,1) if difference.length_squared()>0.000001 else 0.0
	return point.distance_to(a+difference*weight)

func _add(target: Dictionary, peer: int, index: int) -> void:
	if peer<=0 or index<0:return
	if not target.has(peer):target[peer]=[]
	if index not in target[peer]:target[peer].append(index)
