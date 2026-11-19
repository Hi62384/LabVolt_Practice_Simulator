extends RefCounted
## Superposition of linear AC and backward-Euler state for small RLC networks.
## All other circuits remain on the normal transient solver.
const Solver=preload("res://scripts/electronics_solver.gd")

static func descriptor(group: Array,stations: Array,links: Array,dt: float) -> Dictionary:
 if dt<=0.0 or group.size()!=2:return {}
 var dc_index:=-1;var ac_index:=-1
 for index in group:
  var station=stations[index]
  if station.has_method("_fixed_board_expansion"):dc_index=index
  elif station.has_method("_netlist"):ac_index=index
 if dc_index<0 or ac_index<0:return {}
 var dc=stations[dc_index];var ac=stations[ac_index];var lab=ac.lab
 if not dc.fast_linear_ac_enabled or dc.master or dc.generator.enabled or not dc.button_releases.is_empty():return {}
 # Only fixed board expansions are candidates; build() rejects nonlinear parts.
 if not dc.board.is_empty() and (not dc.board_simulating() or dc._fixed_board_expansion().is_empty()):return {}
 if dc.portable_slot and dc.board.is_empty():return {}
 if not lab.powered or not lab.protective_earth_profile.is_empty():return {}
 for lead in lab.completed():
  if str(lead.a).begins_with("IGBT_") or str(lead.b).begins_with("IGBT_"):return {}
 for link in links:
  for endpoint in [link.a,link.b]:
   if int(endpoint.station)==ac_index and str(endpoint.port).begins_with("IGBT_"):return {}
 var key=[group,links,dt,dc.wires,dc.resistance,dc.capacitance,dc.fuse,dc.prune_disconnected_passives,dc.board,dc.board_epoch,dc.revision,dc.portable_slot,dc.board_held,dc.board_stowed,
  lab.terminals,lab.cables,lab.switches,lab.powered,lab.level,lab.frequency,lab.daq_settings,lab.igbt_damping,ac.prune_disconnected]
 return {"key":key,"dc":dc_index,"ac":ac_index,"frequency":lab.frequency,"level":lab.level}

static func build(desc: Dictionary,parts: Array,wires: Array,group: Array) -> Dictionary:
 if desc.is_empty():return {}
 var diodes:=parts.filter(func(part):return part.kind in ["D","LED"])
 if not diodes.is_empty():
  # Limit the number of regions so topology edits do not create long stalls.
  # More diodes and controlled/nonlinear devices retain the full solver.
  if diodes.size()>2:return {}
  var details: Array=[];var diode_indices:={}
  for diode in diodes:
   var resistance:=float(diode.get("ron",2.0));var threshold:=float(diode.get("vf",.65))
   if resistance<.001 or not is_finite(resistance) or not is_finite(threshold):return {}
   var full_id:=str(diode.id);var bias_id:=full_id+"#fast_bias"
   if diode_indices.has(full_id) or parts.any(func(part):return str(part.id)==bias_id):return {}
   var owner:=-1;var local_id:="";var bias_local:=""
   for index in group:
    var station_prefix:="station%d/"%int(index)
    if full_id.begins_with(station_prefix):
     owner=index;local_id=full_id.trim_prefix(station_prefix);bias_local=bias_id.trim_prefix(station_prefix);break
   if owner<0:return {}
   diode_indices[full_id]=details.size()
   details.append({"owner":owner,"id":local_id,"bias_id":bias_id,"bias_local":bias_local,"resistance":resistance,"threshold":threshold})
  var alternatives: Array=[]
  for mask in (1<<diodes.size()):
   var converted: Array=[]
   for source in parts:
    if source.kind not in ["D","LED"]:converted.append(source);continue
    var index: int=diode_indices[str(source.id)];var detail: Dictionary=details[index]
    var conducting: bool=(mask & (1<<index))!=0
    converted.append({"id":source.id,"kind":"R","a":source.a,"b":source.b,"value":detail.resistance if conducting else 1e10})
    if conducting:converted.append({"id":detail.bias_id,"kind":"I","a":source.a,"b":source.b,"value":-float(detail.threshold)/float(detail.resistance)})
   var variant: Dictionary=build(desc,converted,wires,group)
   if variant.is_empty():return {}
   var voltages: Array=[]
   for diode_index in details.size():
    var detail: Dictionary=details[diode_index];var voltage_entry: Array=[]
    for entry in variant.stations[detail.owner].fields.drop:
     if entry[0]==detail.id:voltage_entry=entry;break
    if voltage_entry.is_empty():return {}
    voltages.append(voltage_entry)
    if (mask & (1<<diode_index))==0:continue
    for field in ["i","drop"]:
     var entries: Array=variant.stations[detail.owner].fields[field]
     for index in range(entries.size()-1,-1,-1):
      if entries[index][0]==detail.bias_local:entries.remove_at(index)
      elif field=="i" and entries[index][0]==detail.id:
       var coefficients: PackedFloat64Array=entries[index][1]
       coefficients[0]-=float(detail.threshold)/float(detail.resistance)
       entries[index][1]=coefficients
   variant["diode_voltages"]=voltages
   alternatives.append(variant)
  return {"key":desc.key.duplicate(true),"frequency":desc.frequency,"piecewise":true,"off":alternatives[0],"on":alternatives[1],"alternatives":alternatives,"diodes":details}
 var work: Array=[];var dynamic: Array=[];var states: Array=[]
 var prefix:="station%d/"%int(desc.ac)
 for source in parts:
  if source.kind not in ["R","V","I","C","L","T"] or float(source.get("capacity_ah",0.0))>0.0:return {}
  if source.kind in ["C","L"]:
   var owner:=-1;var local_name:=""
   for index in group:
    var state_prefix:="station%d/"%int(index)
    if str(source.id).begins_with(state_prefix):owner=index;local_name=str(source.id).trim_prefix(state_prefix);break
   if owner<0:return {}
   states.append({"full":str(source.id),"owner":owner,"local":local_name})
   # Bound setup cost and per-step matrix work; larger systems use the normal solver.
   if states.size()>6:return {}
  var part: Dictionary=source.duplicate()
  var id:=str(part.id)
  if part.kind=="V" and id.begins_with(prefix):
   var local:=id.trim_prefix(prefix)
   var amplitude:=0.0;var phase:=0.0;var waveform:=false
   if local=="LOW_0":amplitude=24.0*sqrt(2.0);waveform=true
   elif local in ["P_A","P_B","P_C","PV_A","PV_B","PV_C"]:
    amplitude=120.0*sqrt(2.0)*(float(desc.level) if local.begins_with("PV_") else 1.0)
    phase=[0.0,-TAU/3.0,TAU/3.0][["A","B","C"].find(local.right(1))];waveform=true
   if waveform:dynamic.append({"part":part,"amplitude":amplitude,"phase":phase})
  work.append(part)
 if dynamic.is_empty():return {}
 var probe=Solver.new();var results=[];var next_states=[]
 for basis in 3+states.size():
  for wave in dynamic:
   wave.part.value=0.0 if basis==0 or basis>=3 else float(wave.amplitude)*cos(float(wave.phase)+(PI/2.0 if basis==2 else 0.0))
  probe.memory.clear();probe.time=0.0
  if basis>=3:probe.memory[states[basis-3].full]=1.0
  var result: Dictionary=probe.solve(work,wires,float(desc.key[2]))
  if not result.get("ok",false):return {}
  results.append(result);next_states.append(probe.memory.duplicate())
 var per_station:={}
 for index in group:
  var prefix_station:="station%d/"%int(index)
  var fields:={}
  var transformer_ratios:={}
  for part in work:
   if part.kind=="T" and str(part.id).begins_with(prefix_station):
    transformer_ratios[str(part.id).trim_prefix(prefix_station)]=float(part.ratio)
  for field in ["v","i","drop"]:
   var values: Array=[];var voltage_nodes:={}
   for name in results[0][field]:
    var full:=str(name)
    if not full.begins_with(prefix_station):continue
    # Electrically joined pins share a voltage exactly. Compute their basis
    # once and assign it to every alias when presenting the result.
    var node: String=str(probe.topology.net.get(full,full)) if field=="v" else ""
    if field=="v" and voltage_nodes.has(node):
     values[int(voltage_nodes[node])][2].append(full.trim_prefix(prefix_station))
     continue
    var base: float=results[0][field][name]
    var state_coefficients:=PackedFloat64Array();var has_state_effect:=false
    for state_index in states.size():
     var coefficient:=float(results[3+state_index][field][name])-base
     state_coefficients.append(coefficient)
     has_state_effect=has_state_effect or coefficient!=0.0
    # Many isolated source nodes have no dependence on stored RLC state.
    if not has_state_effect:state_coefficients.clear()
    var coefficients:=PackedFloat64Array([base,float(results[1][field][name])-base,float(results[2][field][name])-base])
    coefficients.append_array(state_coefficients)
    var value_entry: Array=[full.trim_prefix(prefix_station),coefficients]
    if field=="v":
     voltage_nodes[node]=values.size();value_entry.append([])
    values.append(value_entry)
   fields[field]=values
  var islands:={}
  for name in results[0].islands:
   if str(name).begins_with(prefix_station):islands[str(name).trim_prefix(prefix_station)]=results[0].islands[name]
  per_station[index]={"fields":fields,"islands":islands,"transformer_ratios":transformer_ratios}
 var state_transitions: Array=[]
 for state in states:
  var base: float=next_states[0].get(state.full,0.0)
  var coefficients:=PackedFloat64Array()
  for state_index in states.size():coefficients.append(float(next_states[3+state_index].get(state.full,0.0))-base)
  state_transitions.append([base,float(next_states[1].get(state.full,0.0))-base,float(next_states[2].get(state.full,0.0))-base,coefficients])
 return {"key":desc.key.duplicate(true),"frequency":desc.frequency,"stations":per_station,"states":states,"transitions":state_transitions}

static func advance(cache: Dictionary,group: Array,stations: Array,time: float,dt: float) -> bool:
 var angle: float=TAU*float(cache.frequency)*time
 var cosine:=cos(angle);var sine:=sin(angle)
 var previous:=PackedFloat64Array()
 if cache.get("piecewise",false):
  for state in cache.off.states:previous.append(float(stations[state.owner].solver.memory.get(state.local,0.0)))
  # Match the normal solver: start with all diodes off and update all states
  # together until stable. A cycle falls back to ordinary convergence logic.
  var mask:=0;var visited:=0;var chosen: Dictionary={}
  while true:
   if (visited & (1<<mask))!=0:return false
   visited|=1<<mask
   var variant: Dictionary=cache.alternatives[mask];var next_mask:=0
   for diode_index in cache.diodes.size():
    var entry: Array=variant.diode_voltages[diode_index]
    var coefficients: PackedFloat64Array=entry[1]
    var voltage: float=coefficients[0]+coefficients[1]*cosine+coefficients[2]*sine
    for i in range(3,coefficients.size()):voltage+=coefficients[i]*previous[i-3]
    if voltage>float(cache.diodes[diode_index].threshold):next_mask|=1<<diode_index
   if next_mask==mask:chosen=variant;break
   mask=next_mask
  cache=chosen
 if previous.is_empty():
  for state in cache.states:previous.append(float(stations[state.owner].solver.memory.get(state.local,0.0)))
 var next_memory:=PackedFloat64Array()
 for transition in cache.transitions:
  var value: float=float(transition[0])+float(transition[1])*cosine+float(transition[2])*sine
  for i in previous.size():value+=float(transition[3][i])*previous[i]
  next_memory.append(value)
 for index in group:
  var station=stations[index]
  station.solver.time=time
  # The descriptor guarantees the AC wiring is unchanged during this path.
  # Its normal preparation only rebuilds those same wires and records time.
  if station.has_method("_netlist"):station.sample_time=time
  else:station.prepare_step(dt)
  var basis: Dictionary=cache.stations[index]
  var local:={"ok":true,"v":{},"i":{},"drop":{},"mode":{},"charge":{},"winding_currents":{},"islands":basis.islands,"time":time+dt}
  for field in ["v","i","drop"]:
   var output: Dictionary=local[field]
   for entry in basis.fields[field]:
    # The third basis is evaluated at +90 degrees, hence its coefficient is sin(angle).
    var coefficients: PackedFloat64Array=entry[1]
    var value: float=coefficients[0]+coefficients[1]*cosine+coefficients[2]*sine
    for i in range(3,coefficients.size()):value+=coefficients[i]*previous[i-3]
    output[entry[0]]=value
    if field=="v":
     for alias in entry[2]:output[alias]=value
  for id in basis.transformer_ratios:
   var secondary: float=local.i[id]
   local.winding_currents[id]={"secondary":secondary,"primary":-float(basis.transformer_ratios[id])*secondary}
  for i in cache.states.size():
   if int(cache.states[i].owner)==int(index):station.solver.memory[cache.states[i].local]=next_memory[i]
  station.solver.time=time+dt;station.solver.last=local;station.result=local
  station.finish_step()
 return true
