extends RefCounted

const Custom = preload("res://scripts/custom_circuit.gd")
const Board = preload("res://scripts/breadboard_model.gd")
const Geometry = preload("res://scripts/package_editor/package_geometry.gd")
const Shape = preload("res://scripts/inventory_authority/validation.gd")
const Economy = preload("res://scripts/economy/temporary_playtest/policy.gd")
const Persistent = preload("res://scripts/inventory_authority/component_persistence.gd")

static func current(profile: Dictionary, id: String) -> String:
	return str(profile.get("ic_upgrades", {}).get(id, id))

static func interface_signature(bp: Dictionary) -> Array:
	var footprint: Dictionary = bp.get("footprint", {})
	var signature := [int(footprint.get("width",0)),int(footprint.get("height",0)),float(footprint.get("body_height_mm",3.0)),float(footprint.get("thickness_mm",1.6)),bp.get("pin_grid",""),int(bp.get("orientation_turns",0))]
	for pin in bp.get("pins", []):
		signature.append([str(pin.get("id","pin_%d" % signature.size())),Geometry.position(pin),str(pin.get("connector","male_header"))])
	return signature

static func locked(profile: Dictionary, id: String) -> bool:
	if int(profile.get("inventory", {}).get(id, 0)) > 0: return true
	if bool(profile.get("ic_library", {}).get(id, {}).get("manufactured",false)): return true
	for blueprint in profile.get("blueprints", {}).values():
		if blueprint.parts.any(func(part):return part.type == id): return true
	for kit in profile.get("kits", {}).values():
		if kit.board.parts.any(func(part):return part.type == id): return true
	return false

static func quote(profile: Dictionary, old: String, id: String, proposed: Dictionary, reserved: Dictionary, creative := false) -> Dictionary:
	var library: Dictionary = profile.get("blueprints", {})
	if not library.has(old) or current(profile,old) != old: return {"error":"Open the current blueprint revision before updating."}
	if old == id or proposed.get("parent_revision") != old or int(proposed.get("revision",0)) != int(library[old].get("revision",1))+1:
		return {"error":"This draft is based on a different revision."}
	if "ic:"+JSON.stringify(proposed,"",true,true).sha256_text().left(24) != id:
		return {"error":"The proposed revision identifier does not match its circuit."}
	if library[old].get("package","IC") != proposed.get("package"): return {"error":"The updated package type must match the original blueprint."}
	if not creative and locked(profile,old) and interface_signature(library[old]) != interface_signature(proposed):
		return {"error":"The manufactured pin layout and package dimensions are locked. Duplicate to change the footprint."}
	var definitions := library.duplicate()
	definitions[id] = proposed
	if not Shape.definitions(definitions): return {"error":"The proposed revision contains invalid component data."}
	var error := Custom.validate(id,definitions)
	if not error.is_empty(): return {"error":error}
	if _contains_revision(id,old,definitions): return {"error":"A blueprint cannot contain one of its own revisions."}
	var count := 0 if creative else int(profile.inventory.get(old,0))
	var replacements := {old:id}
	if not creative:
		var resolved := replacements.duplicate()
		for package_id in library:
			if current(profile,package_id)==package_id:
				_revise_dependents(package_id,profile,definitions,resolved,replacements)
		if not Shape.definitions(definitions):return {"error":"A dependent blueprint contains invalid component data."}
	var changes := {}
	for previous in replacements:
		var revised: String=replacements[previous]
		var validation := Custom.validate(revised,definitions)
		if not validation.is_empty():return {"error":"%s: %s" % [definitions[revised].name,validation]}
		var copies := 0 if creative else int(profile.inventory.get(previous,0))
		if copies==0:continue
		var before := Custom.materials(previous,definitions)
		var after := Custom.materials(revised,definitions)
		for type in before:changes[type]=int(changes.get(type,0))-int(before[type])*copies
		for type in after:changes[type]=int(changes.get(type,0))+int(after[type])*copies
	var needed := {}
	var returned := {}
	var available := {}
	var missing := {}
	var prices := Board.catalog({"definitions":definitions,"parts":[]})
	var cost := 0
	for type in changes:
		var change: int=changes[type]
		if change < 0: returned[type] = -change
		if change <= 0: continue
		needed[type] = change
		var free := maxi(0, int(profile.inventory.get(type,0))-int(reserved.get(type,0)))
		available[type] = free
		if free >= change: continue
		missing[type] = change-free
		cost += int(prices[type].get("price",0))*int(missing[type])
	return {"error":"","count":count,"needed":needed,"returned":returned,"available":available,"missing":missing,"cost":cost,"definitions":definitions,"replacements":replacements}

static func _revise_dependents(id: String, profile: Dictionary, definitions: Dictionary, resolved: Dictionary, replacements: Dictionary) -> String:
	if resolved.has(id):return resolved[id]
	resolved[id]=id
	var copy: Dictionary=definitions[id].duplicate(true)
	var changed_types := {}
	for part in copy.parts:
		var child := str(part.type)
		if not definitions.has(child):continue
		var latest := current(profile,child)
		var revised := _revise_dependents(latest,profile,definitions,resolved,replacements)
		if revised==latest or interface_signature(definitions[child])!=interface_signature(definitions[revised]):continue
		changed_types[child]=revised
		part.type=revised
	if changed_types.is_empty():return id
	for part in copy.get("layout",{}).get("parts",[]):
		part.type=changed_types.get(part.type,part.type)
	copy.parent_revision=id
	copy.revision=int(copy.get("revision",1))+1
	var revised_id := "ic:"+JSON.stringify(copy,"",true,true).sha256_text().left(24)
	definitions[revised_id]=copy
	resolved[id]=revised_id
	replacements[id]=revised_id
	return revised_id

static func _contains_revision(id: String, previous: String, definitions: Dictionary) -> bool:
	var ancestors := {}
	var version := previous
	while definitions.has(version) and not ancestors.has(version):
		ancestors[version] = true
		version = str(definitions[version].get("parent_revision",""))
	var pending: Array = [id]
	var checked := {}
	while not pending.is_empty():
		var node: String = pending.pop_back()
		if ancestors.has(node): return true
		if checked.has(node): continue
		checked[node] = true
		for part in definitions[node].parts:
			if str(part.type).begins_with("ic:"): pending.append(part.type)
	return false

static func transact(profile: Dictionary, old: String, id: String, proposed: Dictionary, reserved: Dictionary, deployment: Dictionary, mode: String, creative := false) -> Dictionary:
	if not profile.get("pending_trade",{}).is_empty(): return {"error":"Finish the pending trade first."}
	var check := quote(profile,old,id,proposed,reserved,creative)
	if not check.error.is_empty(): return check
	var next := profile.duplicate(true)
	if mode == "purchase":
		if check.missing.is_empty(): return {"error":"All required materials are already available."}
		var debit := Economy.purchase_debit(next.dollars,check.cost,true)
		if not debit.ok: return {"error":debit.error}
		for type in check.missing:
			next.inventory[type] = int(next.inventory.get(type,0))+int(check.missing[type])
		next.dollars = debit.next_balance
		return {"error":"","profile":next,"message":"Missing upgrade components purchased."}
	if mode != "apply": return {"error":"Unknown upgrade operation."}
	if not check.missing.is_empty(): return {"error":"Acquire the missing components before applying the upgrade."}
	var live: Dictionary = deployment.get("counts",{})
	var replaces_live: bool=check.replacements.keys().any(func(type):return int(live.get(type,0))>0)
	if not creative and replaces_live and deployment.get("board",{}).is_empty() and deployment.get("boards",{}).is_empty():
		return {"error":"The deployed circuit is unavailable. Recall it before applying the update."}
	next.blueprints = check.definitions
	if creative: return {"error":"","profile":next,"message":"Creative IC revision saved. Normal inventory was untouched."}
	var registry: Dictionary = next.get("component_instances",{})
	var stored: Array = next.get("dorm",{}).get("instances",[])
	for type in check.needed:
		var amount := int(check.needed[type])
		var instances: Array = registry.keys().filter(func(key):return registry[key].type == type)
		var generic := maxi(0,int(next.inventory.get(type,0))-instances.size()-maxi(0,int(reserved.get(type,0))-instances.filter(func(key):return key in stored or key in deployment.get("instance_ids",[])).size()))
		instances.sort()
		var remove := maxi(0,amount-generic)
		for key in instances:
			if remove == 0: break
			if key in stored or key in deployment.get("instance_ids",[]): continue
			registry.erase(key)
			remove -= 1
		if remove > 0: return {"error":"Some required components are reserved by a deployed or stored circuit."}
		next.inventory[type] = int(next.inventory.get(type,0))-amount
	for type in check.returned:
		next.inventory[type] = int(next.inventory.get(type,0))+int(check.returned[type])
	next.component_instances = registry
	var aliases: Dictionary = next.get("ic_upgrades",{})
	var catalog: Dictionary = next.get("ic_library",{})
	for previous in check.replacements:
		var replacement: String=check.replacements[previous]
		var owned := int(next.inventory.get(previous,0))
		_move_count(next.inventory,previous,replacement)
		for instance in registry.values():
			if instance.type==previous:
				instance.type=replacement
				_preserve_memory(instance,check.definitions[replacement],check.definitions)
		for key in aliases:
			if aliases[key]==previous:aliases[key]=replacement
		aliases[previous]=replacement
		var original: Dictionary=catalog.get(previous,{})
		var revised := original.duplicate(true)
		revised.name=proposed.name if previous==old else str(original.get("name",check.definitions[replacement].name))
		revised.archived=original.get("archived",false) if previous!=old else false
		revised.manufactured=owned>0 or original.get("manufactured",false)
		catalog[replacement]=revised
		original.archived=true
		catalog[previous]=original
	next.ic_upgrades = aliases
	next.ic_library = catalog
	var dorm: Dictionary=next.get("dorm",{})
	var saved: Dictionary=dorm.get("stored_board",{})
	for previous in check.replacements:
		var replacement: String=check.replacements[previous]
		if dorm.has("storage"):_move_count(dorm.storage,previous,replacement)
		if saved.has("counts"):_move_count(saved.counts,previous,replacement)
		for kit in next.kits.values():_move_count(kit.items,previous,replacement)
	for item in next.get("carried_pcbs",[])+dorm.get("carried_components",[]):
		item.type=current(next,str(item.type))
	for bag in dorm.get("backpacks",{}).values():
		for item in bag.items:
			if item.kind=="component":item.type=current(next,str(item.type))
	if saved.has("design"):saved.design=resolve_board(next,saved.design)
	for kit in next.kits.values():
		kit.board = Persistent.materialize(next,resolve_board(next,kit.board))
	var updated_boards := {}
	var boards: Dictionary=deployment.get("boards",{}).duplicate()
	if deployment.has("board") and not deployment.board.is_empty():boards[-1]=deployment.board
	for slot in boards:
		if not boards[slot].parts.any(func(part):return check.replacements.has(part.type)):continue
		var updated := Persistent.materialize(next,resolve_board(next,boards[slot]),[],false)
		var error := Board.validate(updated,{},true)
		if not error.is_empty(): return {"error":"The deployed circuit cannot accept this revision. "+error}
		updated_boards[slot]=updated
	var message := "Blueprint revision saved."
	if check.replacements.size()>1:message += " Updated %d dependent designs." % (check.replacements.size()-1)
	return {"error":"","profile":next,"board":updated_boards.get(-1,{}),"boards":updated_boards,"message":message}

static func _preserve_memory(instance: Dictionary, proposed: Dictionary, definitions: Dictionary) -> void:
	var devices := {}
	# Drop states for removed devices. Stable device IDs preserve unchanged paths.
	var allowed: Array = []
	Board.collect_devices(proposed.parts,definitions,str(instance.root)+"/",allowed,0)
	for device in allowed: devices[device.id] = true
	for key in instance.component_runtime.keys():
		if not devices.has(key): instance.component_runtime.erase(key)

static func _move_count(items: Dictionary, old: String, id: String) -> void:
	if not items.has(old): return
	items[id] = int(items.get(id,0))+int(items[old])
	items.erase(old)

static func resolve_board(profile: Dictionary, saved: Dictionary) -> Dictionary:
	var board := saved.duplicate(true)
	var library: Dictionary = profile.get("blueprints",{})
	var definitions: Dictionary = board.get("definitions",{}).duplicate(true)
	definitions.merge(library,true)
	board.definitions = definitions
	for part in board.parts:
		var old := str(part.type)
		var id := current(profile,old)
		if id == old or not library.has(id) or not library.has(old): continue
		if interface_signature(library[old]) == interface_signature(library[id]): part.type = id
	return board

