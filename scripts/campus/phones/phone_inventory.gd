extends RefCounted
const Tiers=preload("res://scripts/campus/phones/phone_tiers.gd")
const Configuration=preload("res://scripts/campus/items/equipment_configuration.gd")
const MAX_PHONES:=64
static func valid(dorm: Dictionary) -> bool:
	var phones: Variant=dorm.get("smartphones",{})
	var carried: Variant=dorm.get("carry_items",[])
	var bags: Variant=dorm.get("backpacks",{})
	if not phones is Dictionary or phones.size()>MAX_PHONES or not carried is Array or not bags is Dictionary:return false
	var packed:={}
	for bag in bags.values():
		if not bag is Dictionary or not bag.get("items",[]) is Array:return false
		for entry in bag.get("items",[]):
			if entry is Dictionary and entry.get("kind","")=="phone":
				var id: String=str(entry.get("id",""))
				if packed.has(id) or not phones.has(id):return false
				packed[id]=true
	for id in phones:
		if not id is String or id.length()!=32 or not id.is_valid_hex_number() or id!=id.to_lower():return false
		var item: Variant=phones[id]
		if not item is Dictionary or not Tiers.TIERS.has(item.get("tier","")) or item.get("location","") not in ["hotbar","cabinet","packed"]:return false
		if item.size()!=2+int(item.has("configuration")):return false
		if item.has("configuration") and (item.tier!="basic" or Configuration.quote(Configuration.PHONE,0,item.configuration).is_empty()):return false
		if (item.location=="hotbar") != ("phone:"+id in carried):return false
		if (item.location=="packed") != packed.has(id):return false
	for key in carried:
		if key is String and key.begins_with("phone:") and not phones.has(key.trim_prefix("phone:")):return false
	return true

static func carried(dorm: Dictionary) -> bool:
	for key in dorm.get("carry_items",[]):
		if key is String and key.begins_with("phone:") and dorm.get("smartphones",{}).get(key.trim_prefix("phone:"),{}).get("location","")=="hotbar":return true
	var bags: Dictionary=dorm.get("backpacks",{})
	var pending: Array=bags.keys().filter(func(id):return bags[id].location in ["hotbar","back"])
	var visited:={}
	while not pending.is_empty():
		var id: String=str(pending.pop_back())
		if visited.has(id) or not bags.has(id):continue
		visited[id]=true
		for entry in bags[id].items:
			if entry.kind=="bag":pending.append(entry.id)
			elif entry.kind=="phone" and dorm.get("smartphones",{}).get(entry.id,{}).get("location","")=="packed":return true
	return false
