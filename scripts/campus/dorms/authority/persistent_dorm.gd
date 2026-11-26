extends RefCounted
const Edits=preload("res://scripts/campus/dorms/customization/room_edits.gd")
const Rules=preload("res://scripts/campus/dorms/customization/placement_rules.gd")
const Backpacks=preload("res://scripts/campus/dorms/authority/backpack_inventory.gd")
const UsbInventory=preload("res://scripts/campus/computers/usb_inventory.gd")
const LaptopInventory=preload("res://scripts/campus/computers/laptop_inventory.gd")
const PhoneInventory=preload("res://scripts/campus/phones/phone_inventory.gd")
const DEFAULTS=["bed","bedside","wardrobe","study_desk","study_chair","desk_laptop","storage_cabinet","shelf","rug","plant","bedside_lamp","desk_lamp"]
const TOOLS = {"notebook":"Notebook","calculator":"Scientific calculator","pencil_case":"Pencil case","calculator_basic":"Basic calculator","calculator_financial":"Financial calculator","lab_goggles":"Lab goggles","flashlight":"Flashlight","whiteboard":"Whiteboard","marker":"Dry-erase marker"}
const TOOL_PRICES = {"notebook":5,"calculator":24,"pencil_case":9,"calculator_basic":10,"calculator_financial":32,"lab_goggles":12,"flashlight":15,"whiteboard":28,"marker":4}
const STARTER_TOOLS := ["notebook","calculator","pencil_case"]
const CALCULATORS := ["calculator","calculator_basic","calculator_financial"]
const CAPACITY := 64
const NOTEBOOK_PREFIX := "notebook:"
const MAX_NOTEBOOK_COPIES := 64

static func notebook_uid(item: String) -> String:
	if not item.begins_with(NOTEBOOK_PREFIX):return ""
	var uid := item.trim_prefix(NOTEBOOK_PREFIX)
	return uid if uid.length()==32 and uid==uid.to_lower() and not uid.begins_with("-") and uid.is_valid_hex_number(false) else ""

static func is_notebook(item: String) -> bool:
	return item=="notebook" or not notebook_uid(item).is_empty()

static func is_supply(item: String) -> bool:
	return TOOLS.has(item) or is_notebook(item)

static func supply_title(item: String) -> String:
	var uid := notebook_uid(item)
	return str(TOOLS.get(item,"Supply")) if uid.is_empty() else "Notebook · "+uid.right(5)

static func supply_counts(d: Dictionary) -> Dictionary:
	if d.has("supply_counts"):return d.supply_counts.duplicate()
	var counts := {}
	for item in d.get("owned_tools",STARTER_TOOLS):
		counts[item]=1
	return counts

static func carried_calculator(d: Dictionary) -> String:
	for item in d.get("carry_items",[]):
		if item in CALCULATORS:return item
	return ""

static func cabinet_supply_count(d: Dictionary, item: String) -> int:
	var total := int(supply_counts(d).get(item, 0))
	var carried := int(item in d.get("carry_items", []))
	var worn := int(item in d.get("worn_supplies", {}).values())
	return maxi(0, total - carried - worn - Backpacks.supply_count(d, item))

static func paper_supply(paper: Dictionary) -> String:
	if paper.has("supply_id"):return str(paper.supply_id)
	if paper.get("calculator",false):return "calculator"
	if paper.get("notebook",false):return "notebook"
	return ""

static func storage_used(d: Dictionary) -> int:
	var stored_kits: Array = d.get("stored_kits",[])
	var count := stored_kits.size()
	for drive in d.get("usb_drives",{}).values():
		if drive.get("location","")=="cabinet":count+=1
	for laptop in d.get("portable_laptops",{}).values():
		if laptop.get("location","")=="cabinet":count+=1
	for phone in d.get("smartphones",{}).values():
		if phone.get("location","")=="cabinet":count+=1
	for item in supply_counts(d):
		count+=cabinet_supply_count(d,item)
	for amount in d.get("storage",{}).values():count+=int(amount)
	count-=d.get("carried_components",[]).size()
	count-=Backpacks.entries(d,"component").size()
	var bags: Dictionary=d.get("backpacks",{})
	for id in bags:
		if bags[id].location=="cabinet":count+=1+Backpacks.occupied(bags,id)
	var board: Dictionary = d.get("stored_board",{})
	if not board.is_empty():
		count+=1
		for amount in board.get("counts",{}).values():count-=int(amount)
	return count

static func receive_purchase(d: Dictionary, kind: String, id: String, hotbar_limit: int) -> String:
	var carried: Array = d.get("carry_items",[]).duplicate()
	var key := id if kind=="supply" else kind+":"+id
	var compatible := key not in carried and (id not in CALCULATORS or carried_calculator(d).is_empty())
	var destination := ""
	var bag_id := Backpacks.equipped(d)
	if compatible and carried.size()+d.get("carried_components",[]).size()<hotbar_limit:
		carried.append(key)
		d.carry_items=carried
		destination="hotbar"
	elif not bag_id.is_empty() and Backpacks.can_add(d.backpacks[bag_id],kind):
		d.backpacks[bag_id].items.append({"kind":kind,"id":id})
		destination="backpack"
	elif storage_used(d)<CAPACITY:
		destination="dorm cabinet"
		if kind=="kit":
			var stored: Array = d.get("stored_kits",[]).duplicate()
			stored.append(id)
			d.stored_kits=stored
	return destination

static func move_world_supply(profile: Dictionary, item: String, into_hotbar: bool, configuration: Dictionary = {}) -> Dictionary:
	if not is_supply(item) or not profile.has("dorm") or not profile.get("pending_trade",{}).is_empty():
		return fail("Study supply unavailable")
	var next := profile.duplicate(true)
	var d: Dictionary=next.dorm
	var counts := supply_counts(d)
	var carried: Array=d.get("carry_items",[]).duplicate()
	if into_hotbar:
		if item in CALCULATORS and not carried_calculator(d).is_empty():return fail("Store your current calculator first")
		if item in carried:return fail("Store the copy in your hotbar first")
		if carried.size()+d.get("carried_components",[]).size()>=6:return fail("No free hotbar slot")
		if not notebook_uid(item).is_empty() and counts.has(item):return fail("This notebook is already inventoried")
		counts[item]=int(counts.get(item,0))+1
		carried.append(item)
		if not configuration.is_empty():
			if not d.has("notebook_options"):d.notebook_options={}
			d.notebook_options[item]=configuration.duplicate(true)
	else:
		if item not in carried or int(counts.get(item,0))<=0:return fail("The supply is no longer in your hotbar")
		carried.erase(item)
		if int(counts[item])==1:counts.erase(item)
		else:counts[item]=int(counts[item])-1
		d.get("notebook_options",{}).erase(item)
	d.supply_counts=counts
	d.erase("owned_tools")
	d.carry_items=carried
	d.revision=int(d.revision)+1
	if not valid(d,next.get("inventory",{}),next.get("component_instances",{})):return fail("Invalid supply transfer")
	return {"ok":true,"profile":next}

static func carried_count(d: Dictionary, type: String, generic_only := false) -> int:
	var count := 0
	for item in d.get("carried_components",[])+Backpacks.entries(d,"component"):
		if item.type==type and (not generic_only or item.instance.is_empty()):count+=1
	return count

static func move_board(profile: Dictionary, design: Dictionary, counts: Dictionary = {}) -> Dictionary:
	var next := profile.duplicate(true)
	var d: Dictionary = next.get("dorm",{})
	if d.is_empty():return fail("Dorm inventory unavailable")
	var saved: Dictionary = d.get("stored_board",{})
	if not design.is_empty():
		if not saved.is_empty():return fail("The cabinet already contains a board")
		if storage_used(d)>=CAPACITY:return fail("Dorm inventory is full")
		var instances: Array = design.get("instance_ids",{}).values()
		for type in counts:
			var amount := int(d.storage.get(type,0))+int(counts[type])
			if amount>int(next.inventory.get(type,0)):return fail("Board uses unavailable components")
			d.storage[type]=amount
		for id in instances:
			if id in d.instances or not next.get("component_instances",{}).has(id):return fail("Board instance unavailable")
			d.instances.append(id)
		d.stored_board={"design":design.duplicate(true),"counts":counts.duplicate(),"instances":instances}
	else:
		if saved.is_empty():return fail("No board in the cabinet")
		for type in saved.counts:
			var amount := int(d.storage.get(type,0))-int(saved.counts[type])
			if amount<0:return fail("Board storage record is inconsistent")
			if amount==0:d.storage.erase(type)
			else:d.storage[type]=amount
		for id in saved.instances:d.instances.erase(id)
		d.erase("stored_board")
	d.revision=int(d.revision)+1
	if not valid(d,next.get("inventory",{}),next.get("component_instances",{})):return fail("Board exceeds the cabinet save limits")
	return {"ok":true,"profile":next,"board":saved}
static func identity_ok(id: Variant) -> bool:
	return id is String and id.length()==48 and id.is_valid_hex_number() and id==id.to_lower()
static func whole(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and v>=0 and v<=100000 and floor(float(v))==float(v)
static func valid(d: Variant,stock: Dictionary,registry: Dictionary) -> bool:
	if not d is Dictionary or var_to_bytes(d).size()>786432:return false
	if d.get("schema")!=1 or not identity_ok(d.get("owner")) or d.get("room_id")!="dorm_"+str(d.owner):return false
	if d.get("number")!="D-"+str(d.owner):return false
	if d.get("policy") not in ["Private","Invited","Open"] or not d.get("invited") is Array or d.invited.size()>32:return false
	for id in d.invited:
		if not identity_ok(id):return false
	if not d.get("storage") is Dictionary or d.storage.size()>64 or not d.get("instances") is Array:return false
	var carry: Variant = d.get("carry_items",[])
	if not UsbInventory.valid(d):return false
	if not LaptopInventory.valid(d):return false
	if not PhoneInventory.valid(d):return false
	var custody: Variant=d.get("teacher_phone_custody",{})
	if not custody is Dictionary:return false
	if not custody.is_empty():
		if custody.size()!=3 or not custody.get("id") is String or not custody.get("room") is String or not custody.get("teacher") is String:return false
		var held_id: String=str(custody.id)
		if held_id.length()!=32 or not held_id.is_valid_hex_number() or held_id!=held_id.to_lower() or str(custody.room).length()>64 or str(custody.teacher).length()>64:return false
		if d.get("smartphones",{}).get(held_id,{}).get("location","")!="hotbar" or ("phone:"+held_id) not in carry:return false
	if d.has("supply_counts"):
		if not d.supply_counts is Dictionary or d.supply_counts.size()>TOOLS.size()+MAX_NOTEBOOK_COPIES:return false
		var notebook_copies := 0
		for item in d.supply_counts:
			if not item is String or not is_supply(item) or not whole(d.supply_counts[item]) or int(d.supply_counts[item])<1:return false
			if not notebook_uid(item).is_empty():
				notebook_copies+=1
				if int(d.supply_counts[item])!=1 or notebook_copies>MAX_NOTEBOOK_COPIES:return false
	else:
		var tools: Variant = d.get("owned_tools",STARTER_TOOLS)
		if not tools is Array or tools.size()>STARTER_TOOLS.size():return false
		var tool_seen := {}
		for tool in tools:
			if not tool is String or tool not in STARTER_TOOLS or tool_seen.has(tool):return false
			tool_seen[tool]=true
	var counts_by_supply := supply_counts(d)
	var notebooks: Variant=d.get("notebook_options",{})
	if not notebooks is Dictionary or notebooks.size()>MAX_NOTEBOOK_COPIES:return false
	for notebook in notebooks:
		if not notebook is String or notebook_uid(notebook).is_empty() or not counts_by_supply.has(notebook):return false
		if preload("res://scripts/campus/items/equipment_configuration.gd").quote("notebook",0,notebooks[notebook]).is_empty():return false
	if not carry is Array or carry.size()>6:return false
	var carry_seen := {}
	var calculator_count := 0
	for item in carry:
		if not item is String or (item not in counts_by_supply and not item.begins_with("kit:") and not item.begins_with("bag:") and not item.begins_with("usb:") and not item.begins_with("laptop:") and not item.begins_with("phone:")) or carry_seen.has(item):return false
		if item in CALCULATORS:calculator_count+=1
		carry_seen[item]=true
	if calculator_count>1:return false
	var worn: Variant=d.get("worn_supplies",{})
	if not worn is Dictionary or worn.size()>1:return false
	if not worn.is_empty() and (worn.get("head")!="lab_goggles" or int(counts_by_supply.get("lab_goggles",0))<1+(1 if carry_seen.has("lab_goggles") else 0)):
		return false
	var stored_kits: Variant = d.get("stored_kits",[])
	if not stored_kits is Array or stored_kits.size()>CAPACITY:return false
	var seen_kits := {}
	for id in stored_kits:
		if not id is String or seen_kits.has(id) or carry_seen.has("kit:"+id):return false
		seen_kits[id]=true
	if not Backpacks.valid(d,counts_by_supply):return false
	for item in carry:
		if item.begins_with("bag:") and not d.get("backpacks",{}).has(item.trim_prefix("bag:")):return false
	var seen := {};var counts := {}
	for id in d.instances:
		if not id is String or seen.has(id) or not registry.has(id):return false
		seen[id]=true
		var type: String=registry[id].type;counts[type]=int(counts.get(type,0))+1
	for type in d.storage:
		if not type is String or not stock.has(type) or not whole(d.storage[type]) or int(d.storage[type])>int(stock[type]):return false
	for type in counts:
		if int(counts[type])>int(d.storage.get(type,0)):return false
	var board: Variant = d.get("stored_board",{})
	if not board is Dictionary:return false
	if not board.is_empty():
		if not board.get("design") is Dictionary or not board.get("counts") is Dictionary or not board.get("instances") is Array:return false
		if not preload("res://scripts/inventory_authority/validation.gd").board(board.design):return false
		for type in board.counts:
			if not whole(board.counts[type]) or int(board.counts[type])>int(d.storage.get(type,0)):return false
		for id in board.instances:
			if id not in d.instances:return false
	var components: Variant = d.get("carried_components",[])
	if not components is Array or components.size()+carry.size()>6:return false
	var carried_ids := {}
	var carried_types := {}
	for item in components+Backpacks.entries(d,"component"):
		if not item is Dictionary or not item.get("type") is String or not item.get("instance") is String:return false
		if not item.instance.is_empty():
			if not seen.has(item.instance) or carried_ids.has(item.instance) or registry[item.instance].type!=item.type or item.instance in board.get("instances",[]):return false
			carried_ids[item.instance]=true
		carried_types[item.type]=int(carried_types.get(item.type,0))+1
	for type in carried_types:
		if carried_types[type]+int(board.get("counts",{}).get(type,0))>int(d.storage.get(type,0)):return false
		var generic_board := int(board.get("counts",{}).get(type,0))
		for id in board.get("instances",[]):
			if registry[id].type==type:generic_board-=1
		if carried_count(d,type,true)+generic_board>int(d.storage.get(type,0))-int(counts.get(type,0)):return false
	return valid_customization(d.get("customization")) and whole(d.get("revision"))
static func valid_customization(value: Variant) -> bool:
	if not value is Dictionary or not value.get("items") is Array or not value.get("styles") is Dictionary:return false
	for key in value:
		if key not in ["items","styles"]:return false
	for item in value.items:
		if not item is Dictionary:return false
		for key in item:
			if key not in ["id","kind","x","z","rotation"]:return false
	for category in value.styles:
		if not Edits.STYLE_CHOICES.has(category) or value.styles[category] not in Edits.STYLE_CHOICES[category]:return false
	return Rules.validate(value.items,"west").is_empty()
static func migrate(profile: Dictionary,identity: String) -> Dictionary:
	if not identity_ok(identity):return fail("Unbound identity")
	var next := profile.duplicate(true)
	if next.has("dorm"):
		if not valid(next.dorm,next.get("inventory",{}),next.get("component_instances",{})) or next.dorm.owner!=identity:return fail("Invalid saved dorm; original retained")
		if not eligible_layout(next,next.dorm.customization):return fail("Invalid saved furnishings; original retained")
		var changed := false
		var items: Array=next.dorm.customization.items
		next.dorm.customization.items=items.filter(func(item):return item.kind!="desk_laptop")
		changed=items.size()!=next.dorm.customization.items.size()
		if not next.dorm.has("supply_counts"):
			changed=true
			next.dorm.supply_counts=supply_counts(next.dorm)
			next.dorm.erase("owned_tools")
		if int(next.dorm.supply_counts.get("notebook",0))>1:
			var counts: Dictionary=next.dorm.supply_counts
			var existing: int=counts.keys().filter(func(key):return not notebook_uid(key).is_empty()).size()
			var total := mini(int(counts.notebook)-1,MAX_NOTEBOOK_COPIES-existing)
			var replacements: Array[String]=[]
			var ordinal := 1
			while replacements.size()<total:
				var key := NOTEBOOK_PREFIX+("%s:legacy-notebook:%d"%[identity,ordinal]).sha256_text().left(32)
				ordinal+=1
				if counts.has(key):continue
				counts[key]=1
				replacements.append(key)
			var kept_legacy: bool="notebook" in next.dorm.get("carry_items",[])
			for bag in next.dorm.get("backpacks",{}).values():
				for entry in bag.items:
					if entry.kind!="supply" or entry.id!="notebook":continue
					if not kept_legacy:
						kept_legacy=true
						continue
					if not replacements.is_empty():entry.id=replacements.pop_back()
			counts.notebook=int(counts.notebook)-total
			changed=changed or total>0
		return {"ok":true,"profile":next,"changed":changed}
	next.dorm={"schema":1,"owner":identity,"room_id":"dorm_"+identity,"number":"D-"+identity,"policy":"Private","invited":[],"customization":starter_layout(),"storage":{},"instances":[],"revision":0}
	next.dorm.supply_counts={"pencil_case":1} if bool(next.get("purchase_study_tools",false)) else {"pencil_case":1,"calculator":1,"notebook":1}
	return {"ok":true,"profile":next,"changed":true}
static func starter_layout() -> Dictionary:
	var coordinates := {"bed":Vector2(-1.95,-3.55),"bedside":Vector2(-1,-4.2),"wardrobe":Vector2(-2.3,3.65),"study_desk":Vector2(1.65,-2.25),"study_chair":Vector2(1.65,-.95),"desk_laptop":Vector2(1.65,-2.55),"storage_cabinet":Vector2(1.65,3.6),"shelf":Vector2(1.65,4.65),"rug":Vector2(0,.4),"plant":Vector2(.35,4.75),"bedside_lamp":Vector2(-1,-4.2),"desk_lamp":Vector2(.8,-2.65)}
	var items := []
	for id in DEFAULTS:
		if id=="desk_laptop":continue
		items.append({"id":id,"kind":id,"x":coordinates[id].x,"z":coordinates[id].y,"rotation":0})
	return {"items":items,"styles":{}}
static func may_enter(d: Dictionary,owner: String,visitor: String) -> bool:
	return identity_ok(visitor) and (visitor==owner or d.get("policy")=="Open" or (d.get("policy")=="Invited" and visitor in d.get("invited",[])))
static func packed_counts(profile: Dictionary, exclude_kit: String = "") -> Dictionary:
	var counts := {}
	for id in profile.get("kits", {}):
		var kit: Dictionary = profile.kits[id]
		if id == exclude_kit or kit.has("package_draft") or kit.board.get("standalone", false):
			continue
		for type in kit.items:
			counts[type] = int(counts.get(type, 0)) + int(kit.items[type])
	return counts

static func packed_instance_ids(profile: Dictionary, exclude_kit: String = "") -> Array:
	var claims := {}
	for id in profile.get("kits", {}):
		var kit: Dictionary = profile.kits[id]
		if id == exclude_kit or kit.has("package_draft") or kit.board.get("standalone", false):
			continue
		for instance in kit.board.get("instance_ids", {}).values():
			claims[instance] = true
	return claims.keys()

static func stock_used(profile: Dictionary, deployment: Dictionary = {}) -> Dictionary:
	var used := packed_counts(profile)
	var kits: Dictionary = profile.get("kits", {})
	var dorm: Dictionary = profile.get("dorm", {})
	var stored_board: Dictionary = dorm.get("stored_board", {})
	var stored_kit_id := str(stored_board.get("design", {}).get("authority_kit_id", ""))
	var stored_kit: Dictionary = kits.get(stored_kit_id, {})
	if stored_kit.get("board", {}).get("standalone", false) or stored_kit.has("package_draft"):
		stored_kit = {}
	for type in dorm.get("storage", {}):
		var overlap := mini(int(stored_board.get("counts", {}).get(type, 0)), int(stored_kit.get("items", {}).get(type, 0)))
		used[type] = int(used.get(type, 0)) + int(dorm.storage[type]) - overlap
	var deployments: Array=deployment.slots.values() if deployment.has("slots") else [deployment]
	for record in deployments:
		var deployed_kit: Dictionary = kits.get(record.get("kit", ""), {})
		if deployed_kit.get("board", {}).get("standalone", false) or deployed_kit.has("package_draft"):
			deployed_kit = {}
		for type in record.get("counts", {}):
			var packed := int(deployed_kit.get("items", {}).get(type, 0))
			if record.get("kit", "") == stored_kit_id:
				packed -= mini(packed, int(stored_board.get("counts", {}).get(type, 0)))
			var overlap := mini(int(record.counts[type]), packed)
			used[type] = int(used.get(type, 0)) + int(record.counts[type]) - overlap
	return used

static func adds_stock_shortage(before: Dictionary, after: Dictionary, deployment: Dictionary = {}) -> bool:
	var old_used := stock_used(before, deployment)
	var new_used := stock_used(after, deployment)
	for type in new_used:
		var old_shortage := maxi(0, int(old_used.get(type, 0)) - int(before.inventory.get(type, 0)))
		if int(new_used[type]) - int(after.inventory.get(type, 0)) > old_shortage:
			return true
	return false

static func loose_stock(profile: Dictionary) -> Dictionary:
	var reserved := stock_used(profile)
	var stock := {}
	for type in profile.get("inventory",{}):
		var count := int(profile.inventory[type])-int(reserved.get(type,0))
		if count>0:stock[type]=count
	return stock

static func reserved(profile: Dictionary,deployment: Dictionary) -> Dictionary:
	var result: Dictionary=deployment.get("counts",{}).duplicate(true)
	for type in profile.get("dorm",{}).get("storage",{}):result[type]=int(result.get(type,0))+int(profile.dorm.storage[type])
	return result
static func apply_intent(profile: Dictionary,owner: String,intent: Dictionary,deployment: Dictionary={}) -> Dictionary:
	if var_to_bytes(intent).size()>8192:return fail("Dorm intent too large")
	if not profile.get("pending_trade",{}).is_empty():return fail("Finish the pending trade first")
	var m := migrate(profile,owner)
	if not m.ok:return m
	var next: Dictionary=m.profile;var d: Dictionary=next.dorm
	if not intent.get("revision") is int or intent.revision!=int(d.revision):return fail("Stale room revision")
	match intent.get("op"):
		"carry_component", "release_component":
			var type := str(intent.get("item",""))
			var id := str(intent.get("instance",""))
			var components: Array = d.get("carried_components",[]).duplicate(true)
			var part := {"type":type,"instance":id}
			var pickup: bool = intent.op=="carry_component" and intent.get("carry",false)==true
			if pickup:
				if components.size()+d.get("carry_items",[]).size()>=6:return fail("No free hotbar slot")
				components.append(part)
			else:
				if not part in components:return fail("Component is not in your hotbar")
				if intent.op=="carry_component" and storage_used(d)>=CAPACITY:return fail("Dorm inventory is full")
				components.erase(part)
			d.carried_components=components
			if intent.op=="release_component":
				var amount := int(d.storage.get(type,0))-1
				if amount<=0:d.storage.erase(type)
				else:d.storage[type]=amount
				if not id.is_empty():d.instances.erase(id)
		"carry_item":
			var item := str(intent.get("item",""))
			var usb_id:=item.trim_prefix("usb:") if item.begins_with("usb:") else ""
			var laptop_id:=item.trim_prefix("laptop:") if item.begins_with("laptop:") else ""
			var phone_id:=item.trim_prefix("phone:") if item.begins_with("phone:") else ""
			if not usb_id.is_empty() and d.get("usb_drives",{}).get(usb_id,{}).get("location","") in ["connected","lost","handoff"]:return fail("Retrieve this USB drive first")
			if not laptop_id.is_empty() and d.get("portable_laptops",{}).get(laptop_id,{}).get("location","") in ["placed","lost"]:return fail("Retrieve this laptop first")
			if item.begins_with("kit:") and next.get("kits",{}).get(item.trim_prefix("kit:"),{}).get("workspace_only",false):
				return fail("This is a circuit workspace.")
			if not d.supply_counts.has(item) and (not item.begins_with("kit:") or not next.get("kits",{}).has(item.trim_prefix("kit:"))) and (usb_id.is_empty() or not d.get("usb_drives",{}).has(usb_id)) and (laptop_id.is_empty() or not d.get("portable_laptops",{}).has(laptop_id)) and (phone_id.is_empty() or not d.get("smartphones",{}).has(phone_id)):
				return fail("Item unavailable")
			var carried: Array = d.get("carry_items",[]).duplicate()
			if bool(intent.get("carry",false)):
				if item.begins_with("kit:") and Backpacks.has_kit(d, item.trim_prefix("kit:")):
					return fail("Unpack this kit from its backpack first")
				if item.begins_with("kit:") and item.trim_prefix("kit:") not in d.get("stored_kits",[]):
					return fail("This kit is not in the cabinet")
				if not phone_id.is_empty() and d.smartphones[phone_id].location=="packed":
					return fail("Unpack this phone from its backpack first")
				if d.supply_counts.has(item) and cabinet_supply_count(d, item) == 0:
					return fail("No copies of this item are in the cabinet")
				if item in CALCULATORS and not carried_calculator(d).is_empty():return fail("Store your current calculator first")
				if carried.has(item) or carried.size()+d.get("carried_components",[]).size()>=6:return fail("No free hotbar slot")
				carried.append(item)
			elif not carried.has(item):
				return fail("Item is already stored")
			else:
				carried.erase(item)
			var before := storage_used(d)
			if item.begins_with("kit:"):
				var id := item.trim_prefix("kit:")
				var stored: Array = d.get("stored_kits",[]).duplicate()
				if bool(intent.get("carry",false)):stored.erase(id)
				elif not stored.has(id):stored.append(id)
				d.stored_kits=stored
			d.carry_items=carried
			if not usb_id.is_empty():d.usb_drives[usb_id].location="hotbar" if bool(intent.get("carry",false)) else "cabinet"
			if not laptop_id.is_empty():d.portable_laptops[laptop_id].location="hotbar" if bool(intent.get("carry",false)) else "cabinet"
			if not phone_id.is_empty():d.smartphones[phone_id].location="hotbar" if bool(intent.get("carry",false)) else "cabinet"
			if storage_used(d)>maxi(CAPACITY,before):return fail("Dorm inventory is full")
		"rename_usb":
			if not intent.get("name") is String or not UsbInventory.rename(d,str(intent.get("id","")),intent.name):return fail("Invalid USB drive or name")
		"wear_goggles":
			var carried: Array=d.get("carry_items",[]).duplicate()
			if bool(intent.get("wear",false)):
				if not carried.has("lab_goggles") or d.get("worn_supplies",{}).has("head"):return fail("Put goggles in your hotbar first")
				carried.erase("lab_goggles")
				d.worn_supplies={"head":"lab_goggles"}
			else:
				if not d.get("worn_supplies",{}).has("head"):return fail("No goggles equipped")
				if carried.has("lab_goggles") or carried.size()+d.get("carried_components",[]).size()>=6:return fail("Free a hotbar slot first")
				carried.append("lab_goggles")
				d.erase("worn_supplies")
			d.carry_items=carried
		"bag_move","bag_pack","bag_unpack":
			var before := storage_used(d)
			var error := Backpacks.move(d,intent,CALCULATORS)
			if not error.is_empty():return fail(error)
			if storage_used(d)>maxi(CAPACITY,before):return fail("Make room in the cabinet for the backpack and its contents")
		"policy":
			if intent.get("value") not in ["Private","Invited","Open"]:return fail("Invalid policy")
			d.policy=intent.value
		"invite":
			var ids: Variant=intent.get("value")
			if not ids is Array or ids.size()>32:return fail("Invalid invitations")
			for id in ids:
				if not identity_ok(id):return fail("Invalid invitation identity")
			d.invited=ids.duplicate()
		"storage":
			var type: String=str(intent.get("item",""));var delta: Variant=intent.get("delta")
			if not delta is int or delta==0 or absi(delta)>100000 or not next.inventory.has(type):return fail("Invalid quantity")
			if delta>0 and storage_used(d)+delta>CAPACITY:return fail("Dorm inventory is full")
			var amount := int(d.storage.get(type,0))+int(delta)
			if amount<int(d.get("stored_board",{}).get("counts",{}).get(type,0)):return fail("Retrieve the assembled board to access its parts")
			if amount<0 or amount+int(deployment.get("counts",{}).get(type,0))>int(next.inventory[type]):return fail("Unavailable stock")
			var selected: Variant=intent.get("instances",[])
			if not selected is Array or selected.size()>absi(delta):return fail("Invalid instance selection")
			var registry: Dictionary=next.get("component_instances",{});var seen := {}
			for id in selected:
				if not id is String or seen.has(id) or not registry.has(id) or registry[id].type!=type:return fail("Invalid instance")
				seen[id]=true
				if delta>0:
					if id in d.instances or id in deployment.get("instance_ids",[]):return fail("Instance reserved")
					d.instances.append(id)
				else:
					if id not in d.instances:return fail("Instance not stored")
					if id in d.get("stored_board",{}).get("instances",[]):return fail("That instance is installed on the stored board")
					if {"type":type,"instance":id} in d.get("carried_components",[]):return fail("That instance is in your hotbar")
					d.instances.erase(id)
			var registered := 0;var stored := 0
			for id in registry:
				if registry[id].type==type:registered+=1
			for id in d.instances:
				if registry[id].type==type:stored+=1
			if amount<stored or amount-stored>int(next.inventory[type])-registered:return fail("Select specific instances")
			if amount==0:d.storage.erase(type)
			else:d.storage[type]=amount
		"edit":
			if not intent.get("edit") is Dictionary:return fail("Invalid edit")
			if str(intent.edit.get("id",""))=="desk_laptop":return fail("Dorm study computers have been removed")
			var eligible := func(candidate: Dictionary,state: Dictionary) -> bool:return eligible_edit(next,candidate,state)
			var edited: Dictionary=Edits.apply(d.customization,intent.edit,"west",eligible)
			if not edited.ok:return fail(str(edited.error))
			if not eligible_layout(next,edited.state):return fail("Unsupported furnishing or detached surface item")
			d.customization=edited.state
		_:return fail("Unsupported dorm operation")
	if not preload("res://scripts/campus/facilities/accessory_layout.gd").permits_change(profile,next):return fail("Remove an accessory to free a slot")
	d.revision=int(d.revision)+1
	if not valid(d,next.inventory,next.get("component_instances",{})):return fail("Invalid resulting dorm")
	if adds_stock_shortage(profile,next,deployment):return fail("Those components are already packed in a kit")
	return {"ok":true,"profile":next,"changed":true}
static func eligible_layout(profile: Dictionary,state: Dictionary) -> bool:
	for item in state.get("items",[]):
		if not eligible_edit(profile,{"op":"move","item":item},state):return false
	for category in state.get("styles",{}):
		if not eligible_edit(profile,{"op":"style","category":category,"variant":state.styles[category]},state):return false
	return true
static func eligible_edit(profile: Dictionary,intent: Dictionary,state: Dictionary) -> bool:
	if intent.get("op")=="style":
		var defaults := {"wall":"classic","floor":"tile","bedding":"teal","furniture":"oak"}
		return defaults.get(intent.get("category"))==intent.get("variant") or str(intent.get("category"))+":"+str(intent.get("variant")) in profile.get("dorm_unlocks",[])
	var item: Dictionary=intent.get("item",{});var id: String=str(item.get("id",""));var kind: String=str(item.get("kind",""))
	if kind=="display":
		var type := id.trim_prefix("display:")
		if not id.begins_with("display:") or int(profile.get("inventory",{}).get(type,0))<1:return false
		if type.begins_with("ic:") and not profile.get("blueprints",{}).has(type):return false
		var count := 0
		for placed in state.get("items",[]):
			if placed.get("kind")=="display" and placed.get("id")!=id:count+=1
		if count>=3:return false
	elif id not in DEFAULTS or id!=kind:return false
	if kind in Rules.ON_SURFACE:
		var support := "bedside" if kind=="bedside_lamp" else "study_desk"
		var attached := false
		for parent in state.get("items",[]):
			if (parent.get("id")==support or (kind=="display" and parent.get("id")=="shelf")) and Rules.footprint(parent).has_point(Vector2(float(item.get("x",0)),float(item.get("z",0)))):attached=true
		if not attached:return false
	return true
static func public_room(profile: Dictionary) -> Dictionary:
	var d: Dictionary=profile.get("dorm",{})
	var safe := {"items":[],"styles":{}}
	var customization: Dictionary=d.get("customization",{})
	if valid_customization(customization):
		safe=customization.duplicate(true)
		safe.items=safe.items.filter(func(item):return item.kind!="desk_laptop")
	return {"room_id":d.get("room_id",""),"number":d.get("number",""),"policy":d.get("policy","Private"),"customization":safe}
static func fail(message: String) -> Dictionary:return {"ok":false,"error":message}

