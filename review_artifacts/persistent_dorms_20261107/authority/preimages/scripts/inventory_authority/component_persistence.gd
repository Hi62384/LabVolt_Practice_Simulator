extends RefCounted
# Optional schema 1. Persist nonvolatile EEPROM bytes/protection only, never SPI
# shift registers, shared blueprint memory, running firmware, or solver history.
const LIMIT := 786432
static func whole(value: Variant,maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=0 and float(value)<=maximum and float(value)==floor(float(value))
static func valid(runtime: Variant) -> bool:
	if not runtime is Dictionary or runtime.size()>64 or var_to_bytes(runtime).size()>LIMIT:return false
	for id in runtime:
		if not id is String or id.is_empty() or id.length()>256:return false
		var state=runtime[id]
		if preload("res://scripts/physical_resistors.gd").valid(state):continue
		if not state is Dictionary or state.get("schema")!=1 or state.get("model")!="eeprom25":return false
		for key in state:
			if key not in ["schema","model","memory","status"]:return false
		if not state.get("memory") is Dictionary or state.memory.size()>32768 or not whole(state.get("status"),255):return false
		for address in state.memory:
			if not address is String or not address.is_valid_int() or str(int(address))!=address or not whole(int(address),32767) or not whole(state.memory[address],255):return false
	return true
static func registry(value: Variant,stock: Dictionary) -> bool:
	if not value is Dictionary or value.size()>1000:return false
	var counts := {}
	for id in value:
		if not id is String or id.is_empty() or id.length()>96:return false
		var item=value[id]
		if not item is Dictionary or not item.get("type") is String or not item.get("root") is String or not item.root.begins_with("board/") or item.root.length()>256:return false
		for key in item:
			if key not in ["type","root","component_runtime"]:return false
		if not valid(item.get("component_runtime")):return false
		for device in item.component_runtime:
			if device!=item.root and not device.begins_with(item.root+"/"):return false
		counts[item.type]=int(counts.get(item.type,0))+1
		if counts[item.type]>int(stock.get(item.type,0)):return false
	return true
static func capture(states: Dictionary) -> Dictionary:
	var result := {}
	for id in states:
		if states[id] is Dictionary and preload("res://scripts/physical_resistors.gd").valid(states[id].get("resistor")):
			result[str(id)]=states[id].resistor.duplicate(true);continue
		if not states[id] is Dictionary or not states[id].has("memory"):continue
		result[str(id)]={"schema":1,"model":"eeprom25","memory":states[id].memory.duplicate(true),"status":int(states[id].get("status",0))&0x8c}
	return result
static func restore(runtime: Dictionary) -> Dictionary:
	var result := {}
	if not valid(runtime):return result
	for id in runtime:
		if preload("res://scripts/physical_resistors.gd").valid(runtime[id]):result[id]={"resistor":runtime[id].duplicate(true)}
		else:result[id]={"memory":runtime[id].memory.duplicate(true),"status":int(runtime[id].status)&0x8c}
	return result
static func materialize(profile: Dictionary,design: Dictionary) -> Dictionary:
	var result := design.duplicate(true);result.component_runtime={};result.instance_ids={}
	var owned: Dictionary=profile.get("component_instances",{});var used := {}
	var sorted_ids: Array=owned.keys();sorted_ids.sort()
	for part in design.get("parts",[]):
		var selected := str(design.get("instance_ids",{}).get(str(part.id),""))
		if used.has(selected) or not owned.has(selected) or owned[selected].type!=part.type:selected=""
		if selected=="":
			for id in sorted_ids:
				if not used.has(id) and owned[id].type==part.type:selected=id;break
		if selected=="":continue
		used[selected]=true;result.instance_ids[str(part.id)]=selected
		var item: Dictionary=owned[selected];var root := "board/"+str(part.id)
		for device in item.component_runtime:result.component_runtime[root+str(device).trim_prefix(item.root)]=item.component_runtime[device].duplicate(true)
	return result
static func retain(profile: Dictionary,board: Dictionary,states: Dictionary) -> String:
	var runtime := capture(states)
	runtime.merge(preload("res://scripts/physical_resistors.gd").parameters(board),false)
	if not valid(runtime):return "Nonvolatile component state exceeds persistence limits"
	var owned: Dictionary=profile.get("component_instances",{}).duplicate(true)
	var ids: Dictionary=board.get("instance_ids",{}).duplicate(true);var assigned := {};var grouped := {}
	for part in board.get("parts",[]):
		var root := "board/"+str(part.id);var memory := {}
		for device in runtime:
			if device==root or device.begins_with(root+"/"):memory[device]=runtime[device]
		if memory.is_empty():continue
		var instance := str(ids.get(str(part.id),""))
		if assigned.has(instance) or not owned.has(instance) or owned[instance].type!=part.type:instance=""
		if instance=="":
			var candidates: Array=owned.keys();candidates.sort()
			for candidate in candidates:
				if not assigned.has(candidate) and owned[candidate].type==part.type:instance=candidate;break
		if instance=="":instance=Crypto.new().generate_random_bytes(16).hex_encode()
		assigned[instance]=true;ids[str(part.id)]=instance
		owned[instance]={"type":str(part.type),"root":root,"component_runtime":memory}
		grouped.merge(memory)
	if not registry(owned,profile.inventory):return "Nonvolatile instances exceed owned master stock"
	profile.component_instances=owned;board.instance_ids=ids;board.component_runtime=grouped
	return ""
static func selected(profile: Dictionary,items: Dictionary,excluded: Array=[]) -> Dictionary:
	var result := {};var counts := {};var owned: Dictionary=profile.get("component_instances",{})
	var ids: Array=owned.keys();ids.sort()
	for id in ids:
		var type: String=owned[id].type
		if id in excluded or int(counts.get(type,0))>=int(items.get(type,0)):continue
		result[id]=owned[id].duplicate(true);counts[type]=int(counts.get(type,0))+1
	return result

# Match Custom.materials: recipes consume raw leaves, including nested packages.
# The existing root/runtime schema already represents state below a package root.
static func _craft_slots(id: String,definitions: Dictionary,prefix: String,slots: Array) -> void:
	for part in definitions[id].parts:
		var path := prefix+str(part.id)
		if str(part.type).begins_with("ic:"):_craft_slots(str(part.type),definitions,path+"/",slots)
		else:slots.append({"type":str(part.type),"path":path})
static func craft(profile: Dictionary,id: String,definitions: Dictionary,reserved: Dictionary={}) -> String:
	var custom=load("res://scripts/custom_circuit.gd")
	var error: String=custom.validate(id,definitions)
	if error!="":return error
	var inventory: Dictionary=profile.get("inventory",{}).duplicate(true)
	var owned: Dictionary=profile.get("component_instances",{}).duplicate(true)
	if not registry(owned,inventory):return "Invalid owned component instances"
	if not reserved.get("counts",{}) is Dictionary or not reserved.get("instance_ids",[]) is Array:return "Invalid crafting availability"
	var counts: Dictionary=custom.materials(id,definitions)
	var excluded: Array=reserved.get("instance_ids",[])
	var exclusions := {}
	for instance in excluded:
		if not instance is String or exclusions.has(instance) or not owned.has(instance):return "Invalid crafting availability"
		exclusions[instance]=true
	var candidates := {};var generic := {};var ids: Array=owned.keys();ids.sort()
	for type in counts:
		var unavailable: Variant=reserved.get("counts",{}).get(type,0)
		if not whole(unavailable,100000):return "Invalid crafting availability"
		if int(inventory.get(type,0))-int(unavailable)<int(counts[type]):return "Recall deployed components first"
		var total := 0;var held := 0;candidates[type]=[]
		for instance in ids:
			if owned[instance].type!=type:continue
			total+=1
			if instance in excluded:held+=1
			else:candidates[type].append(instance)
		if held>int(unavailable):return "Invalid crafting availability"
		generic[type]=int(inventory.get(type,0))-total-maxi(0,int(unavailable)-held)
		if int(generic[type])<0:return "Recall deployed components first"
		if candidates[type].size()+int(generic[type])<int(counts[type]):return "Recall deployed components first"
	var slots: Array=[];_craft_slots(id,definitions,"",slots)
	var runtime := {};var consumed := [];var root := "board/crafted"
	for slot in slots:
		var type: String=slot.type
		if candidates[type].is_empty():
			if int(generic[type])<1:return "Crafting materials are unavailable"
			generic[type]-=1;continue
		# Same deterministic owned-instance preference as stock transfers.
		var instance: String=candidates[type].pop_front();var item: Dictionary=owned[instance]
		consumed.append(instance)
		for device in item.component_runtime:
			var target := root+"/"+str(slot.path)+str(device).trim_prefix(item.root)
			if runtime.has(target):return "Crafted component state identity conflict"
			runtime[target]=item.component_runtime[device].duplicate(true)
	if not valid(runtime):return "Crafted component state exceeds persistence limits"
	for instance in consumed:owned.erase(instance)
	for type in counts:inventory[type]=int(inventory.get(type,0))-int(counts[type])
	inventory[id]=int(inventory.get(id,0))+1
	if not consumed.is_empty():
		var package := Crypto.new().generate_random_bytes(16).hex_encode()
		while owned.has(package):package=Crypto.new().generate_random_bytes(16).hex_encode()
		owned[package]={"type":id,"root":root,"component_runtime":runtime}
	if not registry(owned,inventory):return "Crafted component instances exceed persistence limits"
	# Publish stock and ownership together only after the complete plan validates.
	profile.inventory=inventory;profile.component_instances=owned
	return ""
