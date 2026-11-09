extends RefCounted

const Dorm = preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
const Board = preload("res://scripts/breadboard_model.gd")
const Profile = preload("res://scripts/electronics_profile.gd")

static func take(profile: Dictionary, source: Dictionary, deployment: Dictionary) -> Dictionary:
	var next := profile.duplicate(true)
	var d: Dictionary = next.dorm
	var item: Dictionary = source.get("item",{})
	var kind := str(item.get("kind",""))
	var id := str(item.get("id",""))
	var key := id if kind=="supply" else kind+":"+id
	match str(source.get("location","")):
		"hotbar":
			var carried: Array = d.get("carried_components",[]) if kind=="component" else d.get("carry_items",[])
			var entry: Variant = {"type":item.get("type",""),"instance":item.get("instance","")} if kind=="component" else key
			if entry not in carried:return Dorm.fail("Item is no longer in your hotbar.")
			carried.erase(entry)
		"packed":
			var bag_id := Dorm.Backpacks.equipped(d)
			var slot := int(source.get("slot",-1))
			if bag_id.is_empty() or bag_id!=source.get("bag") or slot not in range(d.backpacks[bag_id].items.size()):
				return Dorm.fail("Backpack item is no longer available.")
			if d.backpacks[bag_id].items[slot]!=item:return Dorm.fail("Backpack contents changed.")
			d.backpacks[bag_id].items.remove_at(slot)
		"back":
			if kind!="bag" or id.is_empty() or id!=Dorm.Backpacks.equipped(d):return Dorm.fail("Backpack is no longer equipped.")
		"head":
			if kind!="supply" or d.get("worn_supplies",{}).get("head","")!=id:return Dorm.fail("Item is no longer equipped.")
			d.erase("worn_supplies")
		_:return Dorm.fail("Item is unavailable.")
	var parcel := {"item":item.duplicate(true),"kits":{},"tiers":{},"bags":{},"stock":{},"instances":{},"supplies":{},"definitions":{},"carried_stock":{},"carried_instances":[]}
	if not _collect(next,item,parcel,0):return Dorm.fail("Put away any deployed breadboard before discarding its kit.")
	if next.kits.is_empty():
		var replacement := Crypto.new().generate_random_bytes(12).hex_encode()
		next.kits[replacement]={"name":"Circuit workspace","items":{},"board":Board.empty(),"workspace_only":true}
	if not next.kits.has(next.equipped):next.equipped=next.kits.keys()[0]
	for type in parcel.stock:
		if int(next.inventory.get(type,0))<int(parcel.stock[type]):return Dorm.fail("This item is reserved or unavailable.")
		next.inventory[type]-=parcel.stock[type]
	for instance in parcel.instances:next.component_instances.erase(instance)
	for supply in parcel.supplies:
		var counts := Dorm.supply_counts(d)
		if int(counts.get(supply,0))<int(parcel.supplies[supply]):return Dorm.fail("This supply is unavailable.")
		counts[supply]-=parcel.supplies[supply]
		if counts[supply]==0:counts.erase(supply)
		d.supply_counts=counts
		d.erase("owned_tools")
	if Dorm.adds_stock_shortage(profile,next,deployment):return Dorm.fail("This item is reserved or unavailable.")
	d.revision+=1
	if not Profile.valid(next):return Dorm.fail("This item cannot be transferred.")
	return {"ok":true,"profile":next,"parcel":parcel}

static func _collect(profile: Dictionary,item: Dictionary,parcel: Dictionary,depth: int) -> bool:
	if depth>128:return false
	var id := str(item.get("id",""))
	match str(item.get("kind","")):
		"supply":
			if not Dorm.TOOLS.has(id):return false
			parcel.supplies[id]=int(parcel.supplies.get(id,0))+1
		"component":
			var type := str(item.get("type",""))
			var instance := str(item.get("instance",""))
			var d: Dictionary=profile.dorm
			var amount := int(d.storage.get(type,0))
			if amount<=0 or (not instance.is_empty() and instance not in d.instances):return false
			if amount==1:d.storage.erase(type)
			else:d.storage[type]=amount-1
			if not instance.is_empty():
				d.instances.erase(instance)
				parcel.carried_instances.append(instance)
			parcel.carried_stock[type]=int(parcel.carried_stock.get(type,0))+1
			_add_stock(profile,parcel,type,1)
			if not _add_instance(profile,parcel,instance):return false
		"kit":
			if not profile.kits.has(id) or profile.kits[id].has("package_draft") or profile.kits[id].get("workspace_only",false):return false
			var kit: Dictionary=profile.kits[id]
			parcel.kits[id]=kit
			profile.kits.erase(id)
			if profile.get("kit_tiers",{}).has(id):
				parcel.tiers[id]=profile.kit_tiers[id]
				profile.kit_tiers.erase(id)
			for type in kit.items:_add_stock(profile,parcel,type,int(kit.items[type]))
			for instance in kit.board.get("instance_ids",{}).values():
				if not _add_instance(profile,parcel,str(instance)):return false
		"bag":
			if not profile.dorm.get("backpacks",{}).has(id):return false
			var bag: Dictionary=profile.dorm.backpacks[id]
			profile.dorm.backpacks.erase(id)
			parcel.bags[id]=bag
			for child in bag.items:
				if not _collect(profile,child,parcel,depth+1):return false
		_:return false
	return true

static func _add_stock(profile: Dictionary,parcel: Dictionary,type: String,amount: int) -> void:
	parcel.stock[type]=int(parcel.stock.get(type,0))+amount
	_collect_definition(type,profile.get("blueprints",{}),parcel.definitions)

static func _collect_definition(type: String,definitions: Dictionary,out: Dictionary) -> void:
	if out.has(type) or not definitions.has(type):return
	out[type]=definitions[type]
	for part in definitions[type].parts:_collect_definition(str(part.type),definitions,out)

static func _add_instance(profile: Dictionary,parcel: Dictionary,id: String) -> bool:
	if id.is_empty():return true
	if not profile.get("component_instances",{}).has(id) or parcel.instances.has(id):return false
	parcel.instances[id]=profile.component_instances[id]
	return true

static func give(profile: Dictionary, parcel: Dictionary, hotbar_limit: int) -> Dictionary:
	var next := profile.duplicate(true)
	var d: Dictionary=next.dorm
	var item: Dictionary=parcel.item
	var kind := str(item.kind)
	var id := str(item.get("id",""))
	var destination := ""
	if kind=="component":
		if d.get("carry_items",[]).size()+d.get("carried_components",[]).size()<hotbar_limit:
			d.carried_components=d.get("carried_components",[])+[{"type":item.type,"instance":item.instance}]
			destination="hotbar"
		else:
			var bag_id := Dorm.Backpacks.equipped(d)
			if not bag_id.is_empty() and d.backpacks[bag_id].items.size()<int(Dorm.Backpacks.SIZES[d.backpacks[bag_id].size].capacity):
				d.backpacks[bag_id].items.append(item.duplicate(true))
				destination="backpack"
	else:destination=Dorm.receive_purchase(d,kind,id,hotbar_limit)
	if destination in ["","dorm cabinet"]:return Dorm.fail("Free space in your hotbar or backpack first.")
	if not next.has("kit_tiers"):next.kit_tiers={}
	if not next.has("component_instances"):next.component_instances={}
	if not d.has("backpacks"):d.backpacks={}
	for pair in [[next.kits,parcel.kits],[next.kit_tiers,parcel.tiers],[d.backpacks,parcel.bags],[next.component_instances,parcel.instances]]:
		for key in pair[1]:
			if pair[0].has(key):return Dorm.fail("An item with the same ID already exists.")
			pair[0][key]=pair[1][key].duplicate(true) if pair[1][key] is Dictionary else pair[1][key]
	if kind=="bag":d.backpacks[id].location="nested" if destination=="backpack" else "hotbar"
	for type in parcel.definitions:
		if next.blueprints.has(type) and not Profile.same(next.blueprints[type],parcel.definitions[type]):
			return Dorm.fail("A conflicting component blueprint already exists.")
		next.blueprints[type]=parcel.definitions[type].duplicate(true)
	for type in parcel.stock:next.inventory[type]=int(next.inventory.get(type,0))+int(parcel.stock[type])
	for type in parcel.carried_stock:d.storage[type]=int(d.storage.get(type,0))+int(parcel.carried_stock[type])
	d.instances.append_array(parcel.carried_instances)
	var counts := Dorm.supply_counts(d)
	for supply in parcel.supplies:counts[supply]=int(counts.get(supply,0))+int(parcel.supplies[supply])
	d.supply_counts=counts
	d.erase("owned_tools")
	d.revision+=1
	if not Profile.valid(next):return Dorm.fail("This item cannot be added to your inventory.")
	return {"ok":true,"profile":next,"destination":destination}
