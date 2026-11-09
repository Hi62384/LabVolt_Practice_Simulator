extends RefCounted
const Catalog=preload("res://scripts/electronics_catalog.gd")
const Economy=preload("res://scripts/economy/temporary_playtest/policy.gd")
const Persistent=preload("res://scripts/inventory_authority/component_persistence.gd")
const Shape=preload("res://scripts/inventory_authority/validation.gd")
const Board=preload("res://scripts/breadboard_model.gd")
var data := {}
var path := ""
# Explicit operation status for host transactions; legacy callers keep String messages.
var operation_succeeded := false
# Bound by the multiplayer authority adapter; offline callers retain the old API.
var authority_submit := Callable()
var authority_revision := -1
# Host/world supplied availability; never persisted or accepted from metadata.
var craft_reservations := Callable()
var reconciliation_backup := ""
func queued(op: String,args: Array=[]) -> String:
	authority_submit.call(op,args)
	return "Request sent to laboratory host"
static func quantity(value: Variant,maximum: int=100000) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=0 and float(value)<=maximum and float(value)==floor(float(value))
static func same(a: Variant,b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):return float(a)==float(b)
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not same(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in a.size():
			if not same(a[i],b[i]):return false
		return true
	return a==b
func open(identity: String) -> void:
	authority_submit=Callable();authority_revision=-1
	path="user://electronics_"+identity.sha256_text().left(24)+".json"
	data={"schema":1,"dollars":100,"inventory":{"r1000":8,"r220":4,"c1.0":2,"diode":2,"led":2,"button":2,"battery":1},"capacity":40,"equipped":"starter","kits":{"starter":{"name":"Starter kit","items":{"r1000":8,"r220":4,"c1.0":2,"diode":2,"led":2,"button":2,"battery":1},"board":Board.empty()}},"notebook":"","reward_ids":{},"analyzer":false}
	for candidate in [path,path+".bak"]:
		if not FileAccess.file_exists(candidate):continue
		var parsed=JSON.parse_string(FileAccess.get_file_as_string(candidate))
		if valid(parsed):data=parsed;return
	save()
static func valid(value: Variant) -> bool:
	if not value is Dictionary or var_to_bytes(value).size()>1048576:return false
	for key in ["blueprints","applied_trades","pending_trade","authority_credentials"]:
		if not value.get(key,{}) is Dictionary:return false
	if not value.get("analyzer",false) is bool:return false
	var money=value.get("dollars",-1)
	if not (money is int or money is float) or not is_finite(float(money)) or money<0 or money>1000000000:return false
	if not quantity(value.get("capacity",0)):return false
	if not Shape.definitions(value.get("blueprints",{})):return false
	for id in value.get("blueprints",{}):
		if not id is String or not id.begins_with("ic:") or preload("res://scripts/custom_circuit.gd").validate(id,value.blueprints)!="":return false
	if not value is Dictionary or value.get("schema",0)!=1:return false
	if not value.get("inventory") is Dictionary or not value.get("kits") is Dictionary:return false
	for amount in value.inventory.values():
		if not quantity(amount):return false
	if not Persistent.registry(value.get("component_instances",{}),value.inventory):return false
	var known: Dictionary=preload("res://scripts/electronics/component_values/values.gd").augment(preload("res://scripts/custom_circuit.gd").catalog(value.get("blueprints",{})),value.inventory.keys())
	for id in value.inventory:
		if not known.has(id):return false
	if not value.get("reward_ids",{}) is Dictionary:return false
	if not value.get("notebook","") is String:return false
	if int(value.get("capacity",0))<1 or int(value.get("capacity",0))>100000:return false
	if value.kits.is_empty() or value.kits.size()>1000:return false
	for kit in value.kits.values():
		if not kit is Dictionary or not kit.get("name","") is String or not kit.get("items") is Dictionary or not kit.get("board") is Dictionary:return false
		if not Shape.board(kit.board) or Board.validate(kit.board,{},true)!="":return false
		for type in kit.items:
			if not known.has(type) or not quantity(kit.items[type]):return false
		for amount in kit.items.values():
			if not (amount is int or amount is float) or not is_finite(float(amount)) or amount<0 or amount!=floor(amount):return false
	if not value.kits.has(str(value.get("equipped",""))):return false
	if not is_finite(float(value.get("dollars",-1))) or float(value.dollars)<0:return false
	for count in value.inventory.values():
		if not (count is int or count is float) or not is_finite(float(count)) or count<0 or count>100000 or count!=floor(count):return false
	return true
func save() -> Error:
	if not valid(data):return ERR_INVALID_DATA
	if authority_submit.is_valid():queued("metadata",[data.duplicate(true)]);return OK
	if path.is_empty():return OK # Host ledger commits the complete transaction atomically.
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data));file.flush();file.close()
	if FileAccess.file_exists(path):
		var copy := DirAccess.copy_absolute(path,path+".bak")
		if copy!=OK:return copy
	return DirAccess.rename_absolute(path+".tmp",path)
func buy(type: String,quantity: int) -> String:
	operation_succeeded=false
	if authority_submit.is_valid():return queued("buy",[type,quantity])
	if not data.get("pending_trade",{}).is_empty():return "Finish the pending trade first"
	var catalog := catalog()
	if not catalog.has(type) or quantity<1 or quantity>100:return "Invalid purchase"
	var unit_cost: int=preload("res://scripts/custom_circuit.gd").price(type,data.get("blueprints",{})) if type.begins_with("ic:") else int(catalog[type].price)
	var cost: int=unit_cost*quantity
	var debit := Economy.purchase_debit(data.dollars,cost,true)
	if not debit.ok:return debit.error
	var before := data.duplicate(true);data.dollars=debit.next_balance;data.inventory[type]=int(data.inventory.get(type,0))+quantity
	if save()!=OK:data=before;return "Save failed; purchase rolled back"
	operation_succeeded=true
	return "Purchased %d × %s"%[quantity,catalog[type].name]
func buy_configured(base_id: String, settings: Variant, amount: Variant, authority_confirmed: bool=false) -> String:
	operation_succeeded=false
	if authority_submit.is_valid():return queued("buy_configured",[base_id,settings,amount])
	if not authority_confirmed:return "Authenticated host required"
	if not data.get("pending_trade",{}).is_empty():return "Finish the pending trade first"
	var values=preload("res://scripts/electronics/component_values/values.gd")
	var builtins: Dictionary=Catalog.all()
	var configured: Dictionary=values.configure(base_id,settings,builtins)
	if not configured.ok:return configured.error
	var existing: Variant=data.get("inventory",{}).get(configured.id,0)
	if not quantity(existing):return "Invalid existing stock"
	var plan: Dictionary=values.intent(base_id,settings,amount,builtins,int(existing))
	if not plan.ok:return plan.error
	var debit: Dictionary=preload("res://scripts/economy/temporary_playtest/policy.gd").purchase_debit(int(data.dollars),plan.total_price,true)
	if not debit.ok:return debit.error
	var before := data.duplicate(true)
	data.dollars=debit.next_balance;data.inventory[plan.id]=int(existing)+plan.quantity
	if save()!=OK:data=before;return "Save failed; purchase rolled back"
	operation_succeeded=true
	return "Purchased %d × %s"%[plan.quantity,plan.entry.name]

func kit_error(id: String) -> String:
	if not data.kits.has(id):return "Kit not found"
	var used := 0;var catalog := catalog()
	for type in data.kits[id].items:
		var amount := int(data.kits[id].items[type])
		if not catalog.has(type) or amount<0 or amount>int(data.inventory.get(type,0)):return "Kit contains components you no longer own"
		used+=amount*int(catalog[type].space)
	return "Kit exceeds capacity" if used>int(data.capacity) else ""
func set_quantity(type: String,amount: int) -> String:
	var kit: Dictionary=data.kits[data.equipped];var before: Dictionary=kit.items.duplicate()
	kit.items[type]=amount
	var error := kit_error(data.equipped)
	if error!="":kit.items=before;return error
	if save()!=OK:kit.items=before;return "Save failed"
	return "Kit updated"
func reward(id: String,grade: float,difficulty: int,lesson: bool) -> int:
	if authority_submit.is_valid():return 0 # Awards originate only in host grading records.
	if id.is_empty() or id.length()>256 or not data.get("pending_trade",{}).is_empty() or data.reward_ids.has(id) or not is_finite(grade):return 0
	var amount := roundi((10 if lesson else 60)*(clampi(difficulty,0,2)+1)*clampf(grade,0,100)/100.0)
	var credit := Economy.earning_credit(data.dollars,amount,true)
	if not credit.ok:return 0
	var before := data.duplicate(true);data.reward_ids[id]=amount;data.dollars=credit.next_balance
	if save()!=OK:data=before;return 0
	return int(credit.credit)

func duplicate_kit() -> String:
	var before := data.duplicate(true);var id := Crypto.new().generate_random_bytes(12).hex_encode()
	data.kits[id]=data.kits[data.equipped].duplicate(true);data.kits[id].name+=" copy";data.equipped=id
	if save()!=OK:data=before;return "Save failed"
	return "Kit copied"
func delete_kit() -> String:
	if data.kits.size()==1:return "Keep at least one kit"
	var before := data.duplicate(true);data.kits.erase(data.equipped);data.equipped=data.kits.keys()[0]
	if save()!=OK:data=before;return "Save failed"
	return "Kit deleted; owned components are unchanged"
func purchase_bundle(items: Dictionary,price: int) -> String:
	operation_succeeded=false
	if authority_submit.is_valid():return queued("bundle",[items])
	if not data.get("pending_trade",{}).is_empty():return "Finish the pending trade first"
	var debit := Economy.purchase_debit(data.dollars,price,true)
	if not debit.ok:return debit.error
	var before := data.duplicate(true)
	for id in items:
		if not Catalog.all().has(id) or not quantity(items[id],1000) or int(items[id])<1:return "Invalid bundle"
	for id in items:data.inventory[id]=int(data.inventory.get(id,0))+int(items[id])
	data.dollars=debit.next_balance
	if save()!=OK:data=before;return "Save failed; purchase rolled back"
	operation_succeeded=true
	return "Bundle purchased"

func catalog() -> Dictionary:return preload("res://scripts/electronics/component_values/values.gd").augment(preload("res://scripts/custom_circuit.gd").catalog(data.get("blueprints",{})),data.get("inventory",{}).keys())
func save_blueprint(title: String,pin_map: Array=[],description: String="",package: String="IC",width: int=8,height: int=6,color: String="24775b",exposed: Array=[],metadata: Dictionary={}) -> String:
	var before := data.duplicate(true);var design: Dictionary=data.kits[data.equipped].board
	if not data.has("blueprints"):data.blueprints={}
	var blueprint := Board.blueprint(design,title)
	for index in blueprint.parts.size():
		for key in ["code_files","native_firmware","native_sources"]:
			if design.parts[index].has(key):blueprint.parts[index][key]=design.parts[index][key].duplicate(true)
	if design.has("io_controls"):
		blueprint.io_controls={}
		for key in design.io_controls:blueprint.io_controls[str(key).trim_prefix("board/")]=design.io_controls[key].duplicate(true)
	blueprint.description=description.left(1000)
	if package not in ["IC","PCB"]:return "Unknown package type"
	blueprint.package=package
	blueprint.exposed=exposed.duplicate()
	if package in ["IC","PCB"]:
		if width<2 or width>80 or height<2 or height>80:return "Invalid package dimensions"
		blueprint.footprint={"width":width,"height":height,"color":color.left(8)}
		for key in ["body_height_mm","thickness_mm"]:
			if metadata.has(key):blueprint.footprint[key]=metadata[key]
		for key in ["marking","orientation_marker"]:
			if metadata.has(key):blueprint[key]=metadata[key]
		blueprint.layout={"rows":design.rows,"parts":design.parts.duplicate(true),"wires":design.wires.duplicate(true)}
	if not pin_map.is_empty():
		blueprint.pins=[]
		for pin in pin_map:
			if not pin is Dictionary or Board.node(str(pin.get("hole","")),int(design.rows))=="":data=before;return "Each pin needs a valid breadboard hole, such as A1 or F10"
			var mapped := {"name":str(pin.get("name","")).strip_edges().left(24),"node":Board.node(str(pin.hole),int(design.rows))}
			for key in ["id","position","role","connector"]:
				if pin.has(key):mapped[key]=pin[key].duplicate(true) if pin[key] is Dictionary else pin[key]
			blueprint.pins.append(mapped)
	var id := "ic:"+JSON.stringify(blueprint).sha256_text().left(24)
	data.blueprints[id]=blueprint
	var error := preload("res://scripts/custom_circuit.gd").validate(id,data.blueprints)
	if error!="":data=before;return error
	if save()!=OK:data=before;return "Save failed"
	return "Blueprint saved: "+title
func obtain_ic(id: String,craft: bool) -> String:
	operation_succeeded=false
	if authority_submit.is_valid():return queued("obtain",[id,craft])
	if not data.get("pending_trade",{}).is_empty():return "Finish the pending trade first"
	var Custom=preload("res://scripts/custom_circuit.gd");var definitions: Dictionary=data.get("blueprints",{})
	var error: String=Custom.validate(id,definitions)
	if error!="":return error
	var counts: Dictionary=Custom.materials(id,definitions);var cost: int=Custom.price(id,definitions)
	if craft:
		for type in counts:
			if int(data.inventory.get(type,0))<int(counts[type]):return "Missing %d × %s"%[int(counts[type])-int(data.inventory.get(type,0)),Catalog.simulation_entry(str(type)).get("name",type)]
	var debit := Economy.purchase_debit(data.dollars,cost,true)
	if not craft and not debit.ok:return debit.error
	var before := data.duplicate(true)
	if craft:
		var reserved: Variant=craft_reservations.call() if craft_reservations.is_valid() else {}
		if not reserved is Dictionary:return "Crafting availability is unavailable"
		var packing_error: String=Persistent.craft(data,id,definitions,reserved)
		if packing_error!="":data=before;return packing_error
		# Templates reference current ownership; consumed raw state must not survive.
		for kit in data.kits.values():kit.board=Persistent.materialize(data,kit.board)
	else:
		data.dollars=debit.next_balance;data.inventory[id]=int(data.inventory.get(id,0))+1
	if save()!=OK:data=before;return "Save failed; transaction rolled back"
	operation_succeeded=true
	return "Custom IC added to inventory"

func prepare_trade(payload: Dictionary) -> String:
	var id := str(payload.get("id",""))
	if id.is_empty() or id.length()>96 or var_to_bytes(payload).size()>1048576:return "Invalid transaction"
	if data.get("applied_trades",{}).has(id):return ""
	if not data.get("pending_trade",{}).is_empty():return "" if same(data.pending_trade,payload) else "Another transaction is pending"
	if not payload.get("give") is Dictionary or not payload.get("take") is Dictionary or not payload.get("definitions",{}) is Dictionary:return "Invalid offer"
	var definitions: Dictionary=data.get("blueprints",{}).duplicate(true)
	for type in payload.definitions:
		if definitions.has(type) and not same(definitions[type],payload.definitions[type]):return "Blueprint identity conflict"
	definitions.merge(payload.definitions)
	if not Shape.definitions(definitions):return "Invalid custom circuit definitions"
	var available: Dictionary=preload("res://scripts/custom_circuit.gd").catalog(definitions)
	for offer in [payload.give,payload.take]:
		for type in offer:
			if not available.has(type) or not (offer[type] is int or offer[type] is float) or not is_finite(float(offer[type])) or float(offer[type])!=floor(float(offer[type])) or int(offer[type])<0 or int(offer[type])>100000:return "Invalid component quantity"
			if str(type).begins_with("ic:") and preload("res://scripts/custom_circuit.gd").validate(type,definitions)!="":return "Missing custom IC dependencies"
	for type in payload.give:
		if int(payload.give[type])>int(data.inventory.get(type,0)):return "You no longer own all offered components"
	if not Persistent.registry(payload.get("give_instances",{}),payload.give) or not Persistent.registry(payload.get("take_instances",{}),payload.take):return "Invalid persistent component instances"
	for instance in payload.get("give_instances",{}):
		if not same(data.get("component_instances",{}).get(instance),payload.give_instances[instance]):return "Persistent instance is not owned"
	for instance in payload.get("take_instances",{}):
		if data.get("component_instances",{}).has(instance):return "Persistent instance identity conflict"
	var before := data.duplicate(true);data.pending_trade=payload.duplicate(true)
	if save()!=OK:data=before;return "Could not prepare local save"
	return ""
func commit_trade(id: String) -> String:
	if data.get("applied_trades",{}).has(id):return ""
	if data.get("pending_trade",{}).get("id","")!=id:return "Trade save not found; reconnect using the same character"
	var payload: Dictionary=data.pending_trade;var before := data.duplicate(true)
	for type in payload.give:
		if int(data.inventory.get(type,0))<int(payload.give[type]):return "Trade inventory changed; restore your prepared save"
	for type in payload.give:data.inventory[type]=int(data.inventory.get(type,0))-int(payload.give[type])
	for type in payload.take:data.inventory[type]=int(data.inventory.get(type,0))+int(payload.take[type])
	if not data.has("component_instances"):data.component_instances={}
	for instance in payload.get("give_instances",{}):data.component_instances.erase(instance)
	data.component_instances.merge(payload.get("take_instances",{}).duplicate(true))
	if not data.has("blueprints"):data.blueprints={}
	data.blueprints.merge(payload.definitions)
	if not data.has("applied_trades"):data.applied_trades={}
	data.applied_trades[id]=true;data.erase("pending_trade")
	if save()!=OK:data=before;return "Save failed; committed trade will retry"
	return ""
func abort_trade(id: String) -> void:
	if data.get("pending_trade",{}).get("id","")!=id:return
	var before := data.duplicate(true);data.erase("pending_trade")
	if save()!=OK:data=before

func buy_analyzer() -> String:
	operation_succeeded=false
	if authority_submit.is_valid():return queued("analyzer")
	if not data.get("pending_trade",{}).is_empty():return "Finish the pending trade first"
	if data.get("analyzer",false):return "Circuit Analyzer already owned"
	var debit := Economy.purchase_debit(data.dollars,75,true)
	if not debit.ok:return debit.error
	var before := data.duplicate(true);data.dollars=debit.next_balance;data.analyzer=true
	if save()!=OK:data=before;return "Save failed; purchase rolled back"
	operation_succeeded=true
	return "Circuit Analyzer unlocked for all your kits"

const BOXES := {
 "Basic assortment":{"price":12,"draws":6,"pool":{"r1000":25,"r220":25,"c1.0":20,"diode":15,"led":10,"button":5}},
 "Digital assortment":{"price":30,"draws":5,"pool":{"led_green":20,"button":20,"hc00":20,"hc04":15,"flip74":15,"timer555":10}},
 "Builder assortment":{"price":45,"draws":5,"pool":{"pot10k":25,"buzzer":25,"seven_segment":20,"spi_display":15,"lv_mcu":15}}
}
const COSMETICS := {
 "copper_coat":{"name":"Copper-trim laboratory coat","price":35,"settings":{"outfit":"Lab coat","top":"e7eff0","accent":"c7804e"}},
 "gold_safety":{"name":"Gold-frame safety glasses","price":25,"settings":{"glasses":"Safety","accent":"e8bd55"}},
 "blue_gloves":{"name":"Cobalt laboratory gloves","price":20,"settings":{"gloves":true,"glove_color":"426bd4"}},
 "copper_hat":{"name":"Copper hard hat","price":30,"settings":{"hat":"Hard hat","hat_color":"c7804e"}}
}
func buy_box(name: String) -> String:
	operation_succeeded=false
	if authority_submit.is_valid():return queued("box",[name])
	if not data.get("pending_trade",{}).is_empty():return "Finish the pending trade first"
	if not BOXES.has(name):return "Unknown assortment"
	var box: Dictionary=BOXES[name]
	var debit := Economy.purchase_debit(data.dollars,int(box.price),true)
	if not debit.ok:return debit.error
	var before := data.duplicate(true);var rng := RandomNumberGenerator.new();rng.randomize();var won := {}
	for draw in int(box.draws):
		var roll := rng.randi_range(1,100)
		for id in box.pool:
			roll-=int(box.pool[id])
			if roll<=0:won[id]=int(won.get(id,0))+1;break
	data.dollars=debit.next_balance
	for id in won:data.inventory[id]=int(data.inventory.get(id,0))+int(won[id])
	if save()!=OK:data=before;return "Save failed; box purchase rolled back"
	var summary: Array=[]
	for id in won:summary.append("%d × %s"%[won[id],Catalog.all()[id].name])
	operation_succeeded=true
	return "Received: "+", ".join(summary)
func buy_cosmetic(id: String) -> String:
	operation_succeeded=false
	if authority_submit.is_valid():return queued("cosmetic",[id])
	if not data.get("pending_trade",{}).is_empty():return "Finish the pending trade first"
	if not COSMETICS.has(id):return "Unknown accessory"
	if id in data.get("cosmetics",[]):return "Already owned"
	var debit := Economy.purchase_debit(data.dollars,int(COSMETICS[id].price),true)
	if not debit.ok:return debit.error
	var before := data.duplicate(true)
	if not data.has("cosmetics"):data.cosmetics=[]
	data.cosmetics.append(id);data.dollars=debit.next_balance
	if save()!=OK:data=before;return "Save failed; purchase rolled back"
	operation_succeeded=true
	return "Accessory purchased"

func upgrade_capacity() -> String:
	if authority_submit.is_valid():return queued("capacity")
	if not data.get("pending_trade",{}).is_empty():return "Finish the pending trade first"
	var debit := Economy.purchase_debit(data.dollars,50,true)
	if not debit.ok or data.capacity>99980:return "Capacity upgrade unavailable"
	var before := data.duplicate(true);data.dollars=debit.next_balance;data.capacity+=20
	if save()!=OK:data=before;return "Save failed"
	return "Kit capacity increased"
func accept_authority(snapshot: Dictionary) -> Error:
	if not snapshot.get("ok",false) or not snapshot.get("profile") is Dictionary or not valid(snapshot.profile):return ERR_INVALID_DATA
	if int(snapshot.get("revision",-1))<authority_revision:return ERR_INVALID_DATA
	var before := data.duplicate(true);var revision_before := authority_revision
	var credentials: Dictionary=data.get("authority_credentials",{}).duplicate(true)
	if authority_revision<0 and not path.is_empty():
		var comparable := data.duplicate(true);comparable.erase("authority_credentials")
		if not same(comparable,snapshot.profile):
			# Never silently destroy portable offline progress when resuming a host's ledger.
			var backup_path := path+".before_host_"+str(Time.get_unix_time_from_system()).replace(".","_")+".json"
			var backup := FileAccess.open(backup_path,FileAccess.WRITE)
			if backup==null:return FileAccess.get_open_error()
			backup.store_string(JSON.stringify(data));backup.flush();backup.close()
			reconciliation_backup=backup_path
	data=snapshot.profile.duplicate(true);data.authority_credentials=credentials
	authority_revision=int(snapshot.revision)
	var callback := authority_submit;authority_submit=Callable()
	var error := save();authority_submit=callback
	if error!=OK:data=before;authority_revision=revision_before
	return error
