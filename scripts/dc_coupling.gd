extends RefCounted
# Connected stations use one MNA solution: no one-way voltage copying.
const Solver=preload("res://scripts/electronics_solver.gd")
const Board=preload("res://scripts/breadboard_model.gd")
const LinearAC=preload("res://scripts/campus/performance/linear_ac_fast_path.gd")
static func groups_for(count: int, links: Array) -> Array:
	var groups: Array=[]
	for i in count:groups.append([i])
	for link in links:
		var left: Array=[];var right: Array=[]
		for group in groups:
			if int(link.a.station) in group:left=group
			if int(link.b.station) in group:right=group
		if left!=right:left.append_array(right);groups.erase(right)
	return groups

# Called once per frame, after a regular step has built a validated fast cache.
# Other active groups retain the ordinary scheduler and cannot use this plan.
static func linear_frame_plan(stations: Array,links: Array,groups: Array,dt: float) -> Dictionary:
	var main: Array=[];var singles: Array=[]
	for group in groups:
		if group.size()==1 and stations[group[0]].has_method("_netlist"):
			singles.append(int(group[0]))
		elif group.size()==2 and main.is_empty():main=group
		else:return {}
	if main.is_empty():return {}
	var relevant := links.filter(func(link):return int(link.a.station) in main)
	var desc: Dictionary=LinearAC.descriptor(main,stations,relevant,dt)
	if desc.is_empty():return {}
	var dc=stations[int(desc.dc)];var cache: Dictionary=dc.linear_ac_cache
	if cache.is_empty() or not cache.get("eligible",true) or cache.key!=desc.key:return {}
	return {"group":main,"cache":cache,"dc":int(desc.dc),"ac":int(desc.ac),"fuse":dc.fuse,"revision":dc.revision,"board_epoch":dc.board_epoch,"singles":singles}

static func linear_frame_step(plan: Dictionary,stations: Array,dt: float) -> bool:
	var dc=stations[int(plan.dc)];var ac=stations[int(plan.ac)]
	# Either of these may change during finish_step when a protective device trips.
	if not ac.lab.powered or dc.fuse!=plan.fuse or dc.revision!=plan.revision or dc.board_epoch!=plan.board_epoch:return false
	var time:=maxf(dc.solver.time,ac.solver.time)
	if not LinearAC.advance(plan.cache,plan.group,stations,time,dt):return false
	for index in plan.singles:
		stations[index].linked=false;stations[index].step(dt)
	return true

static func step(stations: Array,links: Array,dt: float,groups: Array = []) -> void:
	if groups.is_empty():groups=groups_for(stations.size(),links)
	for group in groups:
		if group.size()==1:
			var single=stations[group[0]]
			single.linked=false
			if single.get("portable_slot")==true and not single.board_simulating():continue
			single.step(dt)
			continue
		var group_links := links.filter(func(link):return int(link.a.station) in group)
		var key := [group,dt,group_links]
		var cacheable := dt>0.0
		var newest := 0.0
		for i in group:newest=maxf(newest,stations[i].solver.time)
		for i in group:
			var station=stations[i]
			station.linked=true
			if not station.has_method("_fixed_board_expansion"):
				cacheable=false
				continue
			station.can_reuse_static_solution=false
			if not station.button_releases.is_empty():station.release_due_buttons(newest)
			var simulating: bool=station.board_simulating()
			key.append([station.revision,station.board_epoch,simulating,station.portable_slot,
				station.master,station.channels,station.current_source,station.auxiliary_sources,
				station.generator,station.resistance,station.capacitance,station.fuse,station.wires])
			if (simulating and station._fixed_board_expansion().is_empty()) or (station.generator.enabled and station.generator.wave!="DC"):
				cacheable=false
		var anchor=stations[group[0]]
		var fast_desc: Dictionary=LinearAC.descriptor(group,stations,group_links,dt)
		if not fast_desc.is_empty():
			var dc_station=stations[int(fast_desc.dc)]
			if not dc_station.linear_ac_cache.is_empty() and dc_station.linear_ac_cache.key==fast_desc.key and dc_station.linear_ac_cache.get("eligible",true):
				if LinearAC.advance(dc_station.linear_ac_cache,group,stations,newest,dt):continue
		var cache: Dictionary=anchor.coupled_cache if cacheable else {}
		if not cache.is_empty() and cache.key==key and cache.solver.time==newest and cache.solver.reuse_flat_solution(cache.batteries,dt):
			for i in group:
				var station=stations[i]
				var local: Dictionary=cache.results[i]
				var prefix := "station%d/"%i
				for part in cache.batteries:
					if not str(part.id).begins_with(prefix):continue
					var id := str(part.id).trim_prefix(prefix)
					local.charge[id]=cache.solver.last.charge[part.id]
					local.mode[id]=cache.solver.last.mode[part.id]
					var battery_key: String=cache.solver._battery_key(part)
					if cache.solver.battery_discharge.has(battery_key):
						station.solver.battery_discharge[battery_key.trim_prefix(prefix)]=cache.solver.battery_discharge[battery_key]
				station.solver.time=cache.solver.time
				local.time=station.solver.time
				station.result=local
				station.solver.last=local
				station.finish_step(true)
			continue
		if anchor.has_method("_fixed_board_expansion"):anchor.coupled_cache={}
		if anchor.solver.network_solver==null:anchor.solver.network_solver=Solver.new()
		var solver=anchor.solver.network_solver
		solver.memory.clear()
		solver.battery_discharge.clear()
		solver.time=newest
		var parts: Array=[]
		var wires: Array=[]
		for i in group:
			var station=stations[i]
			station.solver.time=solver.time
			if station.get("linked_ports") is Dictionary:
				station.linked_ports.clear()
				for link in group_links:
					for endpoint in [link.a,link.b]:
						if int(endpoint.station)==i:station.linked_ports[endpoint.port]=true
			station.prepare_step(dt)
			var prefix := "station%d/"%i
			for name in station.solver.memory:solver.memory[prefix+str(name)]=station.solver.memory[name]
			for name in station.solver.battery_discharge:solver.battery_discharge[prefix+str(name)]=station.solver.battery_discharge[name]
			var sources: Array=station.netlist_active() if station.has_method("netlist_active") else station.netlist()
			var prefixed: Array=[]
			var mapped: Dictionary=station.prefixed_netlist_cache if station.get("prefixed_netlist_cache") is Dictionary else {}
			if not mapped.is_empty() and is_same(mapped.get("source"),sources) and mapped.get("prefix")==prefix:
				prefixed=mapped.parts
				# The AC cache mutates only source values; preserve every other field.
				for part_index in sources.size():
					if sources[part_index].has("value"):prefixed[part_index].value=sources[part_index].value
			else:
				for source in sources:
					var part: Dictionary=source.duplicate()
					for field in ["id","a","b","control","cp","cn","high","coupled"]:
						if part.has(field) and not str(part[field]).is_empty():part[field]=prefix+str(part[field])
					prefixed.append(part)
				if station.get("prefixed_netlist_cache") is Dictionary:
					station.prefixed_netlist_cache={"source":sources,"prefix":prefix,"parts":prefixed}
			parts.append_array(prefixed)
			var local_wires: Array=station.wires.duplicate()
			if not station.board.is_empty() and (not station.has_method("board_simulating") or station.board_simulating()):
				local_wires.append_array(station.board_wires() if station.has_method("board_wires") else Board.wires_only(station.board))
			for wire in local_wires:wires.append([prefix+str(wire[0]),prefix+str(wire[1])])
		for link in group_links:
			wires.append(["station%d/%s"%[link.a.station,link.a.port],"station%d/%s"%[link.b.station,link.b.port]])
		if not fast_desc.is_empty():
			var dc_station=stations[int(fast_desc.dc)]
			if dc_station.linear_ac_cache.is_empty() or dc_station.linear_ac_cache.key!=fast_desc.key:
				dc_station.linear_ac_cache=LinearAC.build(fast_desc,parts,wires,group)
				if dc_station.linear_ac_cache.is_empty():dc_station.linear_ac_cache={"key":fast_desc.key.duplicate(true),"eligible":false}
		var solved: Dictionary=solver.solve(parts,wires,dt,dt==0.)
		var local_results := {}
		for i in group:
			var station=stations[i]
			var prefix := "station%d/"%i
			var local: Dictionary=solved.duplicate()
			for field in ["v","i","drop","mode","islands","charge","winding_currents"]:
				local[field]={}
				for name in solved.get(field,{}):
					if str(name).begins_with(prefix):local[field][str(name).trim_prefix(prefix)]=solved[field][name]
			for name in solver.memory:
				if str(name).begins_with(prefix):station.solver.memory[str(name).trim_prefix(prefix)]=solver.memory[name]
			for name in solver.battery_discharge:
				if str(name).begins_with(prefix):station.solver.battery_discharge[str(name).trim_prefix(prefix)]=solver.battery_discharge[name]
			station.solver.time=solver.time
			station.solver.last=local
			station.result=local
			station.finish_step()
			local_results[i]=local
		if cacheable and solved.get("ok",false) and not parts.any(func(part):return part.kind=="L" or (part.kind=="C" and (part.a!=str(part.id).trim_suffix("cap")+"Ca" or part.b!=str(part.id).trim_suffix("cap")+"Cb"))):
			for part in parts:
				if part.kind!="C":continue
				if float(solver.memory.get(part.id,0.0))!=0.0 or wires.any(func(wire):return part.a in wire or part.b in wire):
					cacheable=false
					break
			if cacheable:
				var batteries := parts.filter(func(part):return part.kind=="V" and float(part.get("capacity_ah",0))>0)
				anchor.coupled_cache={"key":key.duplicate(true),"solver":solver,"batteries":batteries,"results":local_results}
