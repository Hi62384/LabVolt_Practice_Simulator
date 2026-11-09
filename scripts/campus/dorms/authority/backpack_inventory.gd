extends RefCounted

const SIZES := {
	"backpack_small":{"name":"Daypack","capacity":12,"price":18},
	"backpack_medium":{"name":"Campus backpack","capacity":24,"price":36},
	"backpack_large":{"name":"Expedition backpack","capacity":40,"price":62},
	"backpack_giant":{"name":"Giant backpack","capacity":60,"price":95}
}
const MAX_BAGS := 128
const ROOT_LOCATIONS := ["cabinet","hotbar","back","ground"]

static func occupied(bags: Dictionary, id: String) -> int:
	return _occupied(bags,id,{})

static func _occupied(bags: Dictionary, id: String, visited: Dictionary) -> int:
	if visited.has(id) or not bags.has(id):return 0
	visited[id]=true
	var used := 0
	for item in bags[id].items:
		used+=1
		if item.kind=="bag":used+=_occupied(bags,str(item.id),visited)
	return used

static func carried_weight(dorm: Dictionary) -> int:
	var bags: Dictionary=dorm.get("backpacks",{})
	var weight := 0
	for id in bags:
		if bags[id].location in ["hotbar","back"]:weight+=occupied(bags,id)
	return weight

static func speed_multiplier(dorm: Dictionary, hotbar_used: int, hotbar_capacity: int) -> float:
	var load := mini(hotbar_used,hotbar_capacity)+carried_weight(dorm)
	# Use actual carried load so a full small pack feels lighter than a large one.
	return maxf(.02,1.0/(1.0+(1.0/.18-1.0)*pow(load/30.0,3.0)))

static func entries(dorm: Dictionary, kind: String) -> Array:
	var result := []
	for bag in dorm.get("backpacks",{}).values():
		for item in bag.items:
			if item.kind==kind:result.append(item)
	return result

static func supply_count(dorm: Dictionary, id: String) -> int:
	var count := 0
	for item in entries(dorm,"supply"):
		if item.id==id:count+=1
	return count

static func carried_kits(dorm: Dictionary) -> Array:
	var kits: Array = []
	for key in dorm.get("carry_items",[]):
		if str(key).begins_with("kit:"):kits.append(str(key).trim_prefix("kit:"))
	var bags: Dictionary=dorm.get("backpacks",{})
	var pending: Array=bags.keys().filter(func(id):return bags[id].location in ["hotbar","back"])
	var visited := {}
	while not pending.is_empty():
		var id = pending.pop_back()
		if visited.has(id) or not bags.has(id):continue
		visited[id]=true
		for item in bags[id].items:
			if item.kind=="bag":pending.append(item.id)
			elif item.kind=="kit" and item.id not in kits:kits.append(item.id)
	return kits

static func has_kit(dorm: Dictionary, id: String) -> bool:
	for item in entries(dorm, "kit"):
		if item.id == id: return true
	return false

static func equipped(dorm: Dictionary) -> String:
	for id in dorm.get("backpacks",{}):
		if dorm.backpacks[id].location=="back":return id
	return ""

static func valid(dorm: Dictionary, supplies: Dictionary) -> bool:
	var bags: Variant=dorm.get("backpacks",{})
	if not bags is Dictionary or bags.size()>MAX_BAGS:return false
	var parents := {}
	var kits := {}
	var equipped_count := 0
	var used_supplies := {}
	for id in bags:
		if not id is String or id.length()!=24 or not id.is_valid_hex_number():return false
		var bag: Variant=bags[id]
		if not bag is Dictionary or not SIZES.has(bag.get("size")) or not bag.get("items") is Array:return false
		if bag.get("location") not in ROOT_LOCATIONS and bag.get("location")!="nested":return false
		if bag.items.size()>int(SIZES[bag.size].capacity):return false
		if (bag.location=="hotbar")!=("bag:"+id in dorm.get("carry_items",[])):return false
		if bag.location=="back":equipped_count+=1
		if bag.location=="ground":
			var point: Variant=bag.get("position",[])
			if not point is Array or point.size()!=3:return false
			for axis in point:
				if not (axis is float or axis is int) or not is_finite(float(axis)) or absf(float(axis))>1000:return false
		for item in bag.items:
			if not item is Dictionary:return false
			match item.get("kind",""):
				"bag":
					var child: Variant=item.get("id")
					if not child is String or not bags.has(child) or parents.has(child):return false
					parents[child]=id
				"kit":
					var kit: Variant=item.get("id")
					if not kit is String or kits.has(kit) or kit in dorm.get("stored_kits",[]) or "kit:"+kit in dorm.get("carry_items",[]):return false
					kits[kit]=true
				"supply":
					var supply: Variant=item.get("id")
					if not supplies.has(supply):return false
					used_supplies[supply]=int(used_supplies.get(supply,0))+1
				"component":
					if not item.get("type") is String or not item.get("instance") is String:return false
				_:return false
	if equipped_count>1:return false
	for id in bags:
		if (bags[id].location=="nested")!=parents.has(id):return false
		var seen := {}
		var node: String=id
		while parents.has(node):
			if seen.has(node):return false
			seen[node]=true
			node=parents[node]
	for supply in used_supplies:
		var reserved: int=used_supplies[supply]+(1 if supply in dorm.get("carry_items",[]) else 0)+(1 if supply in dorm.get("worn_supplies",{}).values() else 0)
		if reserved>int(supplies[supply]):return false
	return true

static func _hotbar_full(dorm: Dictionary) -> bool:
	return dorm.get("carry_items",[]).size()+dorm.get("carried_components",[]).size()>=6

static func move(dorm: Dictionary, intent: Dictionary, calculators: Array, world := false) -> String:
	var bags: Dictionary=dorm.get("backpacks",{})
	var id := str(intent.get("bag",""))
	if not bags.has(id):return "Backpack unavailable"
	var bag: Dictionary=bags[id]
	var carried: Array=dorm.get("carry_items",[]).duplicate()
	match str(intent.get("op","")):
		"bag_move":
			var destination := str(intent.get("destination",""))
			if destination=="hotbar":
				if bag.location not in (["ground"] if world else ["cabinet","back"]):return "Backpack is unavailable"
				if _hotbar_full(dorm):return "Free a hotbar slot first"
				carried.append("bag:"+id)
				bag.erase("position")
			elif destination=="back" and not world:
				if bag.location!="hotbar" or not equipped(dorm).is_empty():return "Free your Back slot first"
				carried.erase("bag:"+id)
			elif destination=="cabinet" and not world:
				if bag.location not in ["hotbar","back"]:return "Backpack is unavailable"
				carried.erase("bag:"+id)
			elif destination=="ground" and world:
				if bag.location!="hotbar" or not intent.get("position") is Vector3:return "Hold the backpack first"
				var point: Vector3=intent.position
				bag.position=[point.x,point.y,point.z]
				carried.erase("bag:"+id)
			else:return "Invalid backpack move"
			bag.location=destination
		"bag_pack":
			if bag.location!="back":return "Wear this backpack first"
			if bag.items.size()>=int(SIZES[bag.size].capacity):return "Backpack is full"
			var item: Variant=intent.get("item")
			if not item is Dictionary:return "Invalid item"
			var key := str(item.get("id",""))
			match str(item.get("kind","")):
				"bag":
					if not bags.has(key) or bags[key].location!="hotbar":return "Backpack unavailable"
					carried.erase("bag:"+key)
					bags[key].location="nested"
				"kit":
					if "kit:"+key not in carried:return "Kit is not in your hotbar"
					carried.erase("kit:"+key)
				"supply":
					if key not in carried or key.begins_with("kit:") or key.begins_with("bag:"):return "Supply is not in your hotbar"
					carried.erase(key)
				"component":
					var part := {"type":str(item.get("type","")),"instance":str(item.get("instance",""))}
					var parts: Array=dorm.get("carried_components",[]).duplicate(true)
					if part not in parts:return "Component is not in your hotbar"
					parts.erase(part)
					dorm.carried_components=parts
					item={"kind":"component","type":part.type,"instance":part.instance}
				_:return "This item cannot go in a backpack"
			bag.items.append(item if item.kind=="component" else {"kind":str(item.kind),"id":key})
		"bag_unpack":
			if bag.location!="back":return "Wear this backpack first"
			var index: Variant=intent.get("slot")
			if not index is int or index<0 or index>=bag.items.size():return "Backpack slot unavailable"
			var item: Dictionary=bag.items[index]
			if intent.get("destination")=="cabinet":
				match item.kind:
					"bag":bags[item.id].location="cabinet"
					"kit":
						var stored: Array=dorm.get("stored_kits",[]).duplicate()
						stored.append(item.id)
						dorm.stored_kits=stored
					"supply":pass
					_:return "This item cannot go in the cabinet"
				bag.items.remove_at(index)
				return ""
			if _hotbar_full(dorm):return "Free a hotbar slot first"
			match item.kind:
				"bag":
					bags[item.id].location="hotbar"
					carried.append("bag:"+str(item.id))
				"kit":
					carried.append("kit:"+str(item.id))
				"supply":
					if item.id in carried:return "Store the copy in your hotbar first"
					if item.id in calculators:
						for key in carried:
							if key in calculators:return "Store your current calculator first"
					carried.append(item.id)
				"component":
					var parts: Array=dorm.get("carried_components",[]).duplicate(true)
					parts.append({"type":item.type,"instance":item.instance})
					dorm.carried_components=parts
			bag.items.remove_at(index)
		_:return "Invalid backpack action"
	dorm.carry_items=carried
	return ""
