extends RefCounted
const Edits=preload("res://scripts/campus/dorms/customization/room_edits.gd")
const Rules=preload("res://scripts/campus/dorms/customization/placement_rules.gd")
const DEFAULTS=["bed","bedside","wardrobe","study_desk","study_chair","desk_laptop","storage_cabinet","shelf","rug","plant","bedside_lamp","desk_lamp"]
static func identity_ok(id: Variant) -> bool:
	return id is String and id.length()==48 and id.is_valid_hex_number() and id==id.to_lower()
static func whole(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and v>=0 and v<=100000 and floor(float(v))==float(v)
static func valid(d: Variant,stock: Dictionary,registry: Dictionary) -> bool:
	if not d is Dictionary or var_to_bytes(d).size()>32768:return false
	if d.get("schema")!=1 or not identity_ok(d.get("owner")) or d.get("room_id")!="dorm_"+str(d.owner):return false
	if d.get("number")!="D-"+str(d.owner):return false
	if d.get("policy") not in ["Private","Invited","Open"] or not d.get("invited") is Array or d.invited.size()>32:return false
	for id in d.invited:
		if not identity_ok(id):return false
	if not d.get("storage") is Dictionary or d.storage.size()>64 or not d.get("instances") is Array:return false
	var seen := {};var counts := {}
	for id in d.instances:
		if not id is String or seen.has(id) or not registry.has(id):return false
		seen[id]=true
		var type: String=registry[id].type;counts[type]=int(counts.get(type,0))+1
	for type in d.storage:
		if not type is String or not stock.has(type) or not whole(d.storage[type]) or int(d.storage[type])>int(stock[type]):return false
	for type in counts:
		if int(counts[type])>int(d.storage.get(type,0)):return false
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
		return {"ok":true,"profile":next,"changed":false}
	next.dorm={"schema":1,"owner":identity,"room_id":"dorm_"+identity,"number":"D-"+identity,"policy":"Private","invited":[],"customization":starter_layout(),"storage":{},"instances":[],"revision":0}
	return {"ok":true,"profile":next,"changed":true}
static func starter_layout() -> Dictionary:
	var coordinates := {"bed":Vector2(-1.95,-3.55),"bedside":Vector2(-1,-4.2),"wardrobe":Vector2(-2.3,3.65),"study_desk":Vector2(1.65,-2.25),"study_chair":Vector2(1.65,-.95),"desk_laptop":Vector2(1.65,-2.55),"storage_cabinet":Vector2(1.65,3.6),"shelf":Vector2(1.65,4.65),"rug":Vector2(0,.4),"plant":Vector2(.35,4.75),"bedside_lamp":Vector2(-1,-4.2),"desk_lamp":Vector2(.8,-2.65)}
	var items := []
	for id in DEFAULTS:items.append({"id":id,"kind":id,"x":coordinates[id].x,"z":coordinates[id].y,"rotation":0})
	return {"items":items,"styles":{}}
static func may_enter(d: Dictionary,owner: String,visitor: String) -> bool:
	return identity_ok(visitor) and (visitor==owner or d.get("policy")=="Open" or (d.get("policy")=="Invited" and visitor in d.get("invited",[])))
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
			var amount := int(d.storage.get(type,0))+int(delta)
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
			var eligible := func(candidate: Dictionary,state: Dictionary) -> bool:return eligible_edit(next,candidate,state)
			var edited: Dictionary=Edits.apply(d.customization,intent.edit,"west",eligible)
			if not edited.ok:return fail(str(edited.error))
			if not eligible_layout(next,edited.state):return fail("Unsupported furnishing or detached surface item")
			d.customization=edited.state
		_:return fail("Unsupported dorm operation")
	d.revision=int(d.revision)+1
	if not valid(d,next.inventory,next.get("component_instances",{})):return fail("Invalid resulting dorm")
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
	if valid_customization(customization):safe=customization.duplicate(true)
	return {"room_id":d.get("room_id",""),"number":d.get("number",""),"policy":d.get("policy","Private"),"customization":safe}
static func fail(message: String) -> Dictionary:return {"ok":false,"error":message}

