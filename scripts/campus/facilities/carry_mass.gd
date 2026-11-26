extends RefCounted
## All masses are kg. Shared by the local controller and host movement validation.
const LB_TO_KG := .45359237
const SUPPLIES := {"notebook":.30,"calculator":.18,"calculator_basic":.14,"calculator_financial":.20,"pencil_case":.24,"lab_goggles":.08,"flashlight":.25,"whiteboard":.85,"marker":.02}
const BAGS := {"backpack_small":.55,"backpack_medium":.80,"backpack_large":1.10,"backpack_giant":1.50}
const Equipment = preload("res://scripts/campus/items/equipment_configuration.gd")

static func component_mass(type: String) -> float:
	if type.begins_with("battery"):return .05
	if type.begins_with("wire") or type.begins_with("jumper"):return .003
	if type.begins_with("ic:") or type.begins_with("chip"):return .008
	return .002

static func board_mass(board: Dictionary) -> float:
	var result:=.22 if not board.is_empty() else 0.0
	for part in board.get("parts",[]):
		if part is Dictionary:result+=component_mass(str(part.get("type","")))
	result+=.003*float(board.get("wires",[]).size())
	return result

static func kit_mass(profile: Dictionary,id: String,seen: Dictionary) -> float:
	if seen.has("kit/"+id):return 0.0
	seen["kit/"+id]=true
	var kit: Dictionary=profile.get("kits",{}).get(id,{})
	if kit.is_empty():return 0.0
	var total:=.40+board_mass(kit.get("board",{}))
	for type in kit.get("items",{}):total+=component_mass(str(type))*maxi(0,int(kit.items[type]))
	return total

static func bag_mass(profile: Dictionary,id: String,seen: Dictionary) -> float:
	if seen.has("bag/"+id):return 0.0
	seen["bag/"+id]=true
	var bag: Dictionary=profile.get("dorm",{}).get("backpacks",{}).get(id,{})
	if bag.is_empty():return 0.0
	var total: float=float(BAGS.get(str(bag.get("size","")),.55))
	var options: Dictionary=bag.get("configuration",{})
	total+=float(Equipment.value(Equipment.BACKPACK,options,"hardware","pockets",0))*.035
	if float(Equipment.value(Equipment.BACKPACK,options,"hardware","straps",1.0))<1.0:total+=.09
	for item in bag.get("items",[]):
		if not item is Dictionary:continue
		match str(item.get("kind","")):
			"bag":total+=bag_mass(profile,str(item.get("id","")),seen)
			"kit":total+=kit_mass(profile,str(item.get("id","")),seen)
			"supply":total+=float(SUPPLIES.get(str(item.get("id","")).get_slice(":",0),.10))
			"component":total+=component_mass(str(item.get("type","")))
	return total

static func profile_mass(profile: Dictionary, worn_comfort := false) -> float:
	var dorm: Dictionary=profile.get("dorm",{})
	var seen:={};var total:=0.0
	for entry in dorm.get("carry_items",[]):
		var key:=str(entry)
		if key.begins_with("bag:"):total+=bag_mass(profile,key.trim_prefix("bag:"),seen)
		elif key.begins_with("kit:"):total+=kit_mass(profile,key.trim_prefix("kit:"),seen)
		elif not seen.has("supply/"+key):
			seen["supply/"+key]=true
			total+=float(SUPPLIES.get(key.get_slice(":",0),.10))
	for item in dorm.get("carried_components",[]):
		if item is Dictionary:total+=component_mass(str(item.get("type","")))
	for supply in dorm.get("worn_supplies",{}).values():
		var key:=str(supply)
		if not key.is_empty() and not seen.has("supply/"+key):
			seen["supply/"+key]=true
			total+=float(SUPPLIES.get(key,.10))
	for id in dorm.get("backpacks",{}):
		var bag: Dictionary=dorm.backpacks[id]
		if bag.get("location","")!="back":continue
		var comfort: float=Equipment.value(Equipment.BACKPACK,bag.get("configuration",{}),"hardware","straps",1.0) if worn_comfort else 1.0
		total+=bag_mass(profile,str(id),seen)*comfort
	return total

static func gym_mass(peer: int,dumbbells: Array,bars: Dictionary,belts: Array,plates: Array) -> float:
	var total:=0.0;var parents:={}
	for pair in dumbbells:
		if int(pair.get("owner",0))==peer and pair.get("where","") in ["held","stowed"]:total+=float(pair.get("lb",0))*2.0*LB_TO_KG
	for id in bars:
		var bar: Dictionary=bars[id]
		if int(bar.get("owner",0))==peer and bar.get("where","") in ["held","stowed"]:total+=20.0;parents[str(id)]=true
	for id in belts.size():
		var belt: Dictionary=belts[id]
		if int(belt.get("owner",0))==peer and belt.get("where","") in ["held","stowed","worn"]:total+=.8;parents["belt/%d"%id]=true
	for plate in plates:
		if (int(plate.get("owner",0))==peer and plate.get("where","") in ["held","stowed"]) or parents.has(str(plate.get("station",""))):total+=float(plate.get("lb",0))*LB_TO_KG
	return total

static func speed_multiplier(mass_kg: float,strength: float) -> float:
	var threshold:=12.0+28.0*clampf(strength,0.0,1.0)
	var excess:=maxf(0.0,mass_kg-threshold)/threshold
	return clampf(1.0/(1.0+.40*pow(excess,1.2)),.20,1.0)
