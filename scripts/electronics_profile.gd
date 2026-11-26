extends RefCounted
const Dorm=preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
const Catalog=preload("res://scripts/electronics_catalog.gd")
const Economy=preload("res://scripts/economy/temporary_playtest/policy.gd")
const Persistent=preload("res://scripts/inventory_authority/component_persistence.gd")
const Shape=preload("res://scripts/inventory_authority/validation.gd")
const Board=preload("res://scripts/breadboard_model.gd")
const EquipmentConfiguration=preload("res://scripts/campus/items/equipment_configuration.gd")
const KIT_TIERS := {
	"compact":{"name":"Compact kit","capacity":20,"price":12,"rarity":"Common"},
	"standard":{"name":"Standard kit","capacity":40,"price":25,"rarity":"Uncommon"},
	"extended":{"name":"Extended kit","capacity":70,"price":45,"rarity":"Rare"},
	"large":{"name":"Large kit","capacity":120,"price":95,"rarity":"Epic"},
}
var data := {}
var path := ""
# Digest of the last verified primary. A fallback load must not replace its
# only good backup with the damaged primary on the next save.
var primary_digest := ""
# Explicit operation status for host transactions; legacy callers keep String messages.
var operation_succeeded := false
var last_bundle_receipt: Dictionary = {}
var upgraded_board := {}
var upgraded_boards := {}
# Bound by the multiplayer authority adapter; offline callers retain the old API.
var authority_submit := Callable()
var authority_revision := -1
# Host/world supplied availability; never persisted or accepted from metadata.
var craft_reservations := Callable()
var purchase_hotbar_limit := Callable()
var reconciliation_backup := ""
var kit_usage_cache := {}
func queued(op: String,args: Array=[]) -> String:
	var receipt: Variant=authority_submit.call(op,args)
	return "Inventory request could not be queued" if receipt is String and receipt.is_empty() else "Request sent to laboratory host"
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
static func _read_profile_file(file_path: String) -> Variant:
	# JSON.parse_string reports a parser error for damaged files. Recoverable
	# corruption is expected here; use the error-returning parser instead.
	var parser:=JSON.new()
	if parser.parse(FileAccess.get_file_as_string(file_path))!=OK:return null
	return parser.data

func open(identity: String) -> void:
	authority_submit=Callable();authority_revision=-1;primary_digest=""
	path="user://electronics_"+identity.sha256_text().left(24)+".json"
	data={"schema":1,"dollars":100,"inventory":{"r1000":8,"r220":4,"c1.0":2,"diode":2,"led":2,"button":2,"battery":1},"capacity":40,"equipped":"starter","kits":{"starter":{"name":"Starter kit","items":{"r1000":8,"r220":4,"c1.0":2,"diode":2,"led":2,"button":2,"battery":1},"board":Board.empty()}},"notebook":"","reward_ids":{},"analyzer":false}
	for candidate in [path,path+".bak"]:
		if not FileAccess.file_exists(candidate):continue
		var parsed: Variant=_read_profile_file(candidate)
		if parsed is Dictionary and parsed.has("dorm") and not Dorm.valid(parsed.dorm,parsed.get("inventory",{}),parsed.get("component_instances",{})):
			data=parsed;push_error("Corrupt dorm: original file retained; restore profile before playing");return
		if valid(parsed):
			data=parsed
			if candidate==path:primary_digest=FileAccess.get_sha256(path)
			_migrate_dorm(identity)
			_recover_interrupted_usb()
			return
	data.purchase_study_tools=true
	_migrate_dorm(identity)
	save()

func _recover_interrupted_usb() -> void:
	# Profile.open runs outside active gameplay. A connected local drive has no
	# live workstation after restart; only recover archives that still validate.
	var dorm: Dictionary=data.get("dorm",{})
	var drives: Dictionary=dorm.get("usb_drives",{})
	var before: Dictionary=data.duplicate(true)
	var changed:=false
	var archive=preload("res://scripts/campus/computers/usb_archive.gd")
	for id in drives:
		var usb: Dictionary=drives[id]
		if usb.get("location","")!="connected":continue
		var loaded: Dictionary=archive.load(str(dorm.get("owner","")),str(id),int(usb.get("capacity_mb",0)))
		if loaded.has("error"):continue
		usb.location="lost"
		changed=true
	if changed:
		dorm.revision=int(dorm.get("revision",0))+1
		if save()!=OK:data=before
func _migrate_dorm(profile_key: String) -> void:
	var cfg := ConfigFile.new();cfg.load("user://student_identity.cfg")
	var key := profile_key if not profile_key.is_empty() else "__default__"
	var identity := str(cfg.get_value("profiles",key,""))
	if identity.is_empty():
		identity=Crypto.new().generate_random_bytes(24).hex_encode();cfg.set_value("profiles",key,identity)
		if cfg.save("user://student_identity.cfg")!=OK:return
	var result: Dictionary=Dorm.migrate(data,identity)
	if not result.ok:push_error(str(result.error));return
	if result.changed:
		var before := data;data=result.profile
		if save()!=OK:data=before;push_error("Dorm migration save failed")
static func valid(value: Variant) -> bool:
	if not value is Dictionary or var_to_bytes(value).size()>1048576:return false
	if not value.get("blueprints",{}) is Dictionary:return false
	var inventions: Variant=value.get("inventions",{})
	var invention_copies: Variant=value.get("invention_copies",{})
	if not inventions is Dictionary or inventions.size()>64 or not invention_copies is Dictionary or invention_copies.size()>64:return false
	var assembly=preload("res://scripts/campus/facilities/circuit_studio/assembly_model.gd")
	for invention_id in inventions:
		if not invention_id is String or not str(invention_id).begins_with("inv:") or str(invention_id).length()>64 or assembly.validate(str(invention_id),inventions,value.get("blueprints",{}))!="":return false
	for invention_id in invention_copies:
		if not inventions.has(invention_id) or not quantity(invention_copies[invention_id],100):return false
	if value.has("dorm") and not Dorm.valid(value.dorm,value.get("inventory",{}),value.get("component_instances",{})):return false
	for key in ["blueprints","applied_trades","pending_trade","authority_credentials"]:
		if not value.get(key,{}) is Dictionary:return false
	var usb_receipts: Variant=value.get("usb_delivery_receipts",{})
	if not usb_receipts is Dictionary or usb_receipts.size()>1024:return false
	for usb_id in usb_receipts:
		if not usb_id is String or usb_id.length()!=32 or not usb_id.is_valid_hex_number() or not usb_receipts[usb_id] is String or usb_receipts[usb_id].length()!=32 or not usb_receipts[usb_id].is_valid_hex_number():return false
	var usb_pending: Variant=value.get("usb_handoff_pending",{})
	if not usb_pending is Dictionary or usb_pending.size()>128:return false
	for usb_id in usb_pending:
		if not usb_id is String or usb_id.length()!=32 or not usb_id.is_valid_hex_number() or not usb_pending[usb_id] is String or usb_pending[usb_id].length()!=32 or not usb_pending[usb_id].is_valid_hex_number():return false
	var received_pending: Variant=value.get("usb_received_pending",{})
	if not received_pending is Dictionary or received_pending.size()>128:return false
	for usb_id in received_pending:
		var entry: Variant=received_pending[usb_id]
		if not usb_id is String or usb_id.length()!=32 or not usb_id.is_valid_hex_number() or not entry is Dictionary or not entry.get("token") is String or entry.token.length()!=32 or not entry.token.is_valid_hex_number() or not entry.get("host") is String or entry.host.length()>96:return false
	var purchase_pending: Variant=value.get("usb_purchase_pending",{})
	if not purchase_pending is Dictionary or purchase_pending.size()>16:return false
	for usb_id in purchase_pending:
		if not usb_id is String or usb_id.length()!=32 or not usb_id.is_valid_hex_number() or not EquipmentConfiguration.valid_usb_pending(purchase_pending[usb_id]):return false
	var purchase_resolved: Variant=value.get("usb_purchase_resolved",{})
	if not purchase_resolved is Dictionary or purchase_resolved.size()>1024:return false
	for usb_id in purchase_resolved:
		if not usb_id is String or usb_id.length()!=32 or not usb_id.is_valid_hex_number() or purchase_resolved[usb_id]!=true:return false
	var laptop_pending: Variant=value.get("laptop_purchase_pending",{})
	if not laptop_pending is Dictionary or laptop_pending.size()>16:return false
	for laptop_id in laptop_pending:
		var pending: Variant=laptop_pending[laptop_id]
		if not laptop_id is String or laptop_id.length()!=32 or not laptop_id.is_valid_hex_number() or laptop_id!=laptop_id.to_lower() or not pending is Dictionary or not preload("res://scripts/campus/computers/laptop_inventory.gd").TIERS.has(pending.get("tier","")) or not pending.get("host") is String or pending.host.is_empty() or pending.host.length()>96:return false
		if pending.size()!=2+int(pending.has("configuration")):return false
		if pending.has("configuration") and (pending.tier!="basic" or EquipmentConfiguration.quote(EquipmentConfiguration.LAPTOP,0,pending.configuration).is_empty()):return false
	var laptop_resolved: Variant=value.get("laptop_purchase_resolved",{})
	if not laptop_resolved is Dictionary or laptop_resolved.size()>1024:return false
	for laptop_id in laptop_resolved:
		if not laptop_id is String or laptop_id.length()!=32 or not laptop_id.is_valid_hex_number() or laptop_resolved[laptop_id]!=true:return false
	var phone_pending: Variant=value.get("phone_purchase_pending",{})
	if not phone_pending is Dictionary or phone_pending.size()>16:return false
	for phone_id in phone_pending:
		var pending: Variant=phone_pending[phone_id]
		if not phone_id is String or phone_id.length()!=32 or not phone_id.is_valid_hex_number() or phone_id!=phone_id.to_lower() or not pending is Dictionary or not preload("res://scripts/campus/phones/phone_tiers.gd").TIERS.has(pending.get("tier","")) or not pending.get("host") is String or pending.host.is_empty() or pending.host.length()>96:return false
		if pending.size()!=2+int(pending.has("configuration")):return false
		if pending.has("configuration") and EquipmentConfiguration.quote(EquipmentConfiguration.PHONE,0,pending.configuration).is_empty():return false
	var phone_resolved: Variant=value.get("phone_purchase_resolved",{})
	if not phone_resolved is Dictionary or phone_resolved.size()>1024:return false
	for phone_id in phone_resolved:
		if not phone_id is String or phone_id.length()!=32 or not phone_id.is_valid_hex_number() or phone_resolved[phone_id]!=true:return false
	var write_pending: Variant=value.get("usb_write_pending",{})
	if not write_pending is Dictionary or write_pending.size()>16:return false
	for token in write_pending:
		var item: Variant=write_pending[token]
		if not token is String or token.length()!=32 or not token.is_valid_hex_number() or not item is Dictionary or item.size()!=3 or not item.get("id") is String or item.id.length()!=32 or not item.id.is_valid_hex_number() or int(item.get("capacity",0)) not in [8,32,64,150] or not item.get("host") is String or item.host.is_empty() or item.host.length()>96:return false
	var write_decisions: Variant=value.get("usb_write_decisions",{})
	if not write_decisions is Dictionary or write_decisions.size()>1024:return false
	for token in write_decisions:
		if not token is String or token.length()!=32 or not token.is_valid_hex_number() or not write_decisions[token] is bool:return false
	var write_completed: Variant=value.get("usb_write_completed",{})
	if not write_completed is Dictionary or write_completed.size()>1024:return false
	for token in write_completed:
		if not token is String or token.length()!=32 or not token.is_valid_hex_number() or write_completed[token]!=true:return false
	if not value.get("analyzer",false) is bool:return false
	var money=value.get("dollars",-1)
	if not (money is int or money is float) or not is_finite(float(money)) or money<0 or money>1000000000:return false
	if not quantity(value.get("capacity",0)):return false
	if not Shape.definitions(value.get("blueprints",{})):return false
	var carried_pcbs: Variant=value.get("carried_pcbs",[])
	if not carried_pcbs is Array or carried_pcbs.size()>6:return false
	for pcb in carried_pcbs:
		if not pcb is Dictionary or not pcb.get("type") is String or not pcb.type.begins_with("ic:") or pcb.type.length()>64:return false
		if not pcb.get("instance") is String or pcb.instance.length()>64:return false
	var library: Variant = value.get("ic_library", {})
	if not library is Dictionary or library.size() > 1000: return false
	for id in library:
		var metadata: Variant = library[id]
		if not value.get("blueprints", {}).has(id) or not metadata is Dictionary: return false
		if not metadata.get("name", "") is String or str(metadata.get("name", "")).length() > 40: return false
		if not metadata.get("archived", false) is bool or not metadata.get("manufactured",false) is bool: return false
	var revisions: Variant = value.get("ic_upgrades",{})
	if not revisions is Dictionary or revisions.size()>1000: return false
	for old in revisions:
		var id: Variant = revisions[old]
		if not id is String or not value.get("blueprints",{}).has(id) or not value.blueprints.has(old) or revisions.has(id): return false
	for id in value.get("blueprints",{}):
		if not id is String or not id.begins_with("ic:") or preload("res://scripts/custom_circuit.gd").validate(id,value.blueprints)!="":return false
	if not value is Dictionary or value.get("schema",0)!=1:return false
	if not value.get("inventory") is Dictionary or not value.get("kits") is Dictionary:return false
	if value.has("circuit_draft") and (not Shape.board(value.circuit_draft) or Board.validate(value.circuit_draft,{},true)!=""):return false
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
	var kit_tiers: Variant = value.get("kit_tiers",{})
	if not kit_tiers is Dictionary or kit_tiers.size()>1000:return false
	for id in kit_tiers:
		if not id is String or not kit_tiers[id] is String or not KIT_TIERS.has(kit_tiers[id]):return false
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
	if authority_submit.is_valid():
		var receipt: Variant=authority_submit.call("metadata",[data.duplicate(true)])
		return ERR_BUSY if receipt is String and receipt.is_empty() else OK
	if path.is_empty():return OK # Host ledger commits the complete transaction atomically.
	var serialized:=JSON.stringify(data)
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:return FileAccess.get_open_error()
	file.store_string(serialized);file.flush()
	var write_error:=file.get_error()
	file.close()
	if write_error!=OK:return write_error
	if FileAccess.file_exists(path):
		var disk_digest:=FileAccess.get_sha256(path)
		if disk_digest.is_empty():return ERR_FILE_CANT_READ
		# Avoid revalidating large profiles on each autosave; if the file was
		# externally changed or this instance recovered a backup, validate the
		# actual bytes before rotating. Never back up a corrupt primary.
		var can_backup: bool=(not primary_digest.is_empty() and disk_digest==primary_digest) or valid(_read_profile_file(path))
		if can_backup:
			# Stage separately so an interrupted copy cannot destroy the previous
			# known-good backup while the primary is still being committed.
			var copy:=DirAccess.copy_absolute(path,path+".bak.tmp")
			if copy!=OK:return copy
			var backup_result:=DirAccess.rename_absolute(path+".bak.tmp",path+".bak")
			if backup_result!=OK:return backup_result
	var result:=DirAccess.rename_absolute(path+".tmp",path)
	if result==OK:primary_digest=serialized.sha256_text()
	return result
func buy(type: String,quantity: int) -> String:
	operation_succeeded=false
	if authority_submit.is_valid():return queued("buy",[type,quantity])
	if not data.get("pending_trade",{}).is_empty():return "Finish the pending trade first"
	var catalog := catalog()
	if not catalog.has(type) or quantity<1 or quantity>100:return "Invalid purchase"
	if type.begins_with("ic:"):
		var routing_error: String=preload("res://scripts/custom_circuit.gd").manufacturing_error(type,data.get("blueprints",{}))
		if not routing_error.is_empty():return routing_error
	var unit_cost: int=preload("res://scripts/custom_circuit.gd").price(type,data.get("blueprints",{})) if type.begins_with("ic:") else int(catalog[type].price)
	var cost: int=unit_cost*quantity
	var debit := Economy.purchase_debit(data.dollars,cost,true)
	if not debit.ok:return debit.error
	var before := data.duplicate(true);data.dollars=debit.next_balance;data.inventory[type]=int(data.inventory.get(type,0))+quantity
	if type.begins_with("ic:"): mark_manufactured(type)
	if save()!=OK:data=before;return "Save failed; purchase rolled back"
	operation_succeeded=true
	return "Purchased %d × %s"%[quantity,catalog[type].name]
func resale_price(type: String) -> int:
	var entry: Dictionary = catalog().get(type, {})
	var price := int(entry.get("price", 0))
	if type.begins_with("ic:") and not entry.is_empty():
		price = preload("res://scripts/custom_circuit.gd").price(type, data.blueprints)
	return maxi(1, floori(price * .5)) if price > 0 else 0

func sell_component(type: String) -> String:
	operation_succeeded = false
	if authority_submit.is_valid(): return queued("sell_component", [type])
	if not data.get("pending_trade", {}).is_empty(): return "Finish the pending trade first"
	var price := resale_price(type)
	if price <= 0: return "This component cannot be sold"
	var reservations: Dictionary = craft_reservations.call() if craft_reservations.is_valid() else {"counts": Dorm.reserved(data, {}), "instance_ids": data.get("dorm", {}).get("instances", [])}
	var count := int(data.inventory.get(type, 0))
	if count <= int(reservations.counts.get(type, 0)) or kit_available(type)==0: return "Unpack, recall or retrieve a copy before selling"
	var credit := Economy.earning_credit(data.dollars, price, true)
	if not credit.ok: return credit.error
	var before := data.duplicate(true)
	var instances: Dictionary = data.get("component_instances", {})
	var matching: Array = instances.keys().filter(func(id): return instances[id].type == type)
	var packed_ids := Dorm.packed_instance_ids(data)
	var reserved_instances := matching.filter(func(id): return id in reservations.instance_ids)
	var reserved_generic := maxi(0, int(reservations.counts.get(type, 0)) - reserved_instances.size())
	if count - matching.size() <= reserved_generic:
		matching.sort()
		for id in matching:
			if id not in reservations.instance_ids and id not in packed_ids:
				instances.erase(id)
				break
	data.inventory[type] = count - 1
	for kit in data.kits.values():
		if int(kit.items.get(type, 0)) >= count:
			if count == 1: kit.items.erase(type)
			else: kit.items[type] = count - 1
	data.dollars = credit.next_balance
	if save() != OK:
		data = before
		return "Save failed; sale rolled back"
	operation_succeeded = true
	return "Component sold for $%d" % price if int(credit.credit) > 0 else "Component sold · playtest earnings disabled"

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

func buy_study_tool(id: String, hotbar_limit := 6, configuration: Variant = {}) -> String:
	if purchase_hotbar_limit.is_valid():hotbar_limit = mini(hotbar_limit,purchase_hotbar_limit.call())
	if authority_submit.is_valid():return queued("study_tool",[id,hotbar_limit,configuration])
	operation_succeeded=false
	var configured_backpack := id==EquipmentConfiguration.BACKPACK
	var backpack_quote: Dictionary={}
	if configured_backpack:
		backpack_quote=EquipmentConfiguration.quote(id,int(Dorm.Backpacks.SIZES.backpack_small.price),configuration)
		if backpack_quote.is_empty():return "Invalid backpack configuration"
		configuration=backpack_quote.configuration
		id=str(EquipmentConfiguration.value(id,configuration,"hardware","size",""))
	var bag: Dictionary=Dorm.Backpacks.SIZES.get(id,{})
	if (not Dorm.TOOL_PRICES.has(id) and bag.is_empty()) or not data.has("dorm"):return "Study supply unavailable"
	if not data.get("pending_trade",{}).is_empty():return "Finish the pending trade first"
	var counts := Dorm.supply_counts(data.dorm)
	if int(counts.get(id,0))>=100000:return "Supply quantity limit reached"
	if id=="notebook" and counts.keys().filter(func(key):return not Dorm.notebook_uid(key).is_empty()).size()>=Dorm.MAX_NOTEBOOK_COPIES:return "Notebook limit reached"
	if not bag.is_empty() and data.dorm.get("backpacks",{}).size()>=Dorm.Backpacks.MAX_BAGS:return "Backpack limit reached"
	var price := int(Dorm.TOOL_PRICES.get(id,bag.get("price",0)))
	if not configuration is Dictionary:return "Invalid study supply configuration"
	if configured_backpack:
		price=int(backpack_quote.price)
	elif not configuration.is_empty():
		if id!=EquipmentConfiguration.NOTEBOOK:return "Invalid study supply configuration"
		var quote := EquipmentConfiguration.quote(id,price,configuration)
		if quote.is_empty():return "Invalid notebook configuration"
		configuration=quote.configuration
		price=int(quote.price)
	var debit := Economy.purchase_debit(int(data.dollars),price,true)
	if not debit.ok:return debit.error
	var before := data.duplicate(true)
	var item_id := id if bag.is_empty() else Crypto.new().generate_random_bytes(12).hex_encode()
	if id=="notebook":item_id=Dorm.NOTEBOOK_PREFIX+Crypto.new().generate_random_bytes(16).hex_encode()
	var destination := Dorm.receive_purchase(data.dorm,"supply" if bag.is_empty() else "bag",item_id,hotbar_limit)
	if destination.is_empty():return "No room in your hotbar, backpack, or dorm cabinet"
	if bag.is_empty():
		counts[item_id]=int(counts.get(item_id,0))+1
	else:
		if not data.dorm.has("backpacks"):data.dorm.backpacks={}
		var location := "nested" if destination=="backpack" else "cabinet" if destination=="dorm cabinet" else "hotbar"
		data.dorm.backpacks[item_id]={"size":id,"location":location,"items":[]}
		if configured_backpack:data.dorm.backpacks[item_id].configuration=configuration
	data.dorm.supply_counts=counts
	if id==EquipmentConfiguration.NOTEBOOK and not configuration.is_empty():
		if not data.dorm.has("notebook_options"):data.dorm.notebook_options={}
		data.dorm.notebook_options[item_id]=configuration
	data.dorm.erase("owned_tools")
	data.dorm.revision=int(data.dorm.revision)+1
	data.dollars=debit.next_balance
	if save()!=OK:data=before;return "Purchase could not be saved"
	operation_succeeded=true
	return "%s added to your %s" % [Dorm.TOOLS.get(id,bag.get("name","Supply")),destination]

func buy_usb(capacity_mb: int, hotbar_limit := 6, requested_id := "", configuration: Variant = {}) -> String:
	if purchase_hotbar_limit.is_valid():hotbar_limit=mini(hotbar_limit,purchase_hotbar_limit.call())
	operation_succeeded=false
	var usb=preload("res://scripts/campus/computers/usb_inventory.gd")
	if not usb.PRICES.has(capacity_mb) or not data.has("dorm"):return "USB drive unavailable"
	if not configuration is Dictionary:return "Invalid USB configuration"
	var price:=int(usb.PRICES[capacity_mb])
	var selected: Dictionary={}
	if not configuration.is_empty():
		var quote:=EquipmentConfiguration.quote(EquipmentConfiguration.USB,int(usb.PRICES[8]),configuration)
		if quote.is_empty() or EquipmentConfiguration.value(EquipmentConfiguration.USB,quote.configuration,"hardware","storage",0)!=capacity_mb:return "Invalid USB configuration"
		price=int(quote.price)
		selected=quote.configuration
	if not data.get("pending_trade",{}).is_empty():return "Finish the pending trade first"
	var dorm: Dictionary=data.dorm
	var id:=requested_id if not requested_id.is_empty() else Crypto.new().generate_random_bytes(16).hex_encode()
	if id.length()!=32 or not id.is_valid_hex_number() or id!=id.to_lower() or dorm.get("usb_drives",{}).has(id):return "Invalid USB drive identity"
	if authority_submit.is_valid():
		if data.get("usb_purchase_pending",{}).size()>=16:return "Too many USB purchases are awaiting confirmation"
		var archive=preload("res://scripts/campus/computers/usb_archive.gd")
		if FileAccess.file_exists(archive.path(dorm.owner,id)):return "USB identity already exists"
		if archive.save(dorm.owner,id,"USB drive",capacity_mb,preload("res://scripts/campus/computers/device_filesystem.gd").new(capacity_mb*1024*1024))!=OK:return "Could not create the USB archive"
		var before: Dictionary=data.duplicate(true)
		if not data.has("usb_purchase_pending"):data.usb_purchase_pending={}
		data.usb_purchase_pending[id]=capacity_mb if selected.is_empty() else {"capacity_mb":capacity_mb,"configuration":selected}
		var callback:=authority_submit;authority_submit=Callable()
		var error:=save();authority_submit=callback
		if error!=OK:data=before;return "Could not save the pending USB purchase"
		return queued("buy_usb",[capacity_mb,hotbar_limit,id] if selected.is_empty() else [capacity_mb,hotbar_limit,id,selected])
	if dorm.get("usb_drives",{}).size()>=usb.MAX_DRIVES:return "USB drive limit reached"
	var carried: Array=dorm.get("carry_items",[])
	var hotbar: bool=carried.size()+dorm.get("carried_components",[]).size()<hotbar_limit
	if not hotbar and Dorm.storage_used(dorm)>=Dorm.CAPACITY:return "No room in your hotbar or dorm cabinet"
	var debit:=Economy.purchase_debit(int(data.dollars),price,true)
	if not debit.ok:return debit.error
	var before:=data.duplicate(true)
	if not path.is_empty():
		var archive=preload("res://scripts/campus/computers/usb_archive.gd")
		if FileAccess.file_exists(archive.path(dorm.owner,id)):return "USB identity already exists"
		if archive.save(dorm.owner,id,"USB drive",capacity_mb,preload("res://scripts/campus/computers/device_filesystem.gd").new(capacity_mb*1024*1024))!=OK:return "Could not create the USB archive"
	if not dorm.has("usb_drives"):dorm.usb_drives={}
	dorm.usb_drives[id]={"name":"USB drive","capacity_mb":capacity_mb,"location":"hotbar" if hotbar else "cabinet"}
	if not selected.is_empty():dorm.usb_drives[id].configuration=selected
	if hotbar:dorm.carry_items=carried+["usb:"+id]
	dorm.revision=int(dorm.revision)+1;data.dollars=debit.next_balance
	if save()!=OK:data=before;return "USB purchase could not be saved"
	operation_succeeded=true
	return "%d MB USB drive added to your %s" % [capacity_mb,"hotbar" if hotbar else "dorm cabinet"]

func buy_portable_laptop(tier: String, hotbar_limit := 6, requested_id := "", configuration: Variant = {}) -> String:
	if purchase_hotbar_limit.is_valid():hotbar_limit=mini(hotbar_limit,purchase_hotbar_limit.call())
	operation_succeeded=false
	var laptops=preload("res://scripts/campus/computers/laptop_inventory.gd")
	if not laptops.TIERS.has(tier) or not data.has("dorm"):return "Laptop unavailable"
	if not configuration is Dictionary:return "Invalid laptop configuration"
	var price:=int(laptops.TIERS[tier].price)
	var selected: Dictionary={}
	if not configuration.is_empty():
		var quote:=EquipmentConfiguration.quote(EquipmentConfiguration.LAPTOP,price,configuration)
		if tier!="basic" or quote.is_empty():return "Invalid laptop configuration"
		price=int(quote.price)
		selected=quote.configuration
	if not data.get("pending_trade",{}).is_empty():return "Finish the pending trade first"
	var dorm: Dictionary=data.dorm
	var id:=requested_id if not requested_id.is_empty() else Crypto.new().generate_random_bytes(16).hex_encode()
	if id.length()!=32 or not id.is_valid_hex_number() or id!=id.to_lower() or dorm.get("portable_laptops",{}).has(id):return "Invalid laptop identity"
	if authority_submit.is_valid():
		if data.get("laptop_purchase_pending",{}).size()>=16:return "Too many laptop purchases are awaiting confirmation"
		var authority: Object=authority_submit.get_object()
		var host: String=str(authority.get("bound_host")) if is_instance_valid(authority) else ""
		if host.is_empty():return "Host inventory is not ready"
		var original: Dictionary=data.duplicate(true)
		if not data.has("laptop_purchase_pending"):data.laptop_purchase_pending={}
		data.laptop_purchase_pending[id]={"tier":tier,"host":host}
		if not selected.is_empty():data.laptop_purchase_pending[id].configuration=selected
		var callback:=authority_submit;authority_submit=Callable()
		var error:=save();authority_submit=callback
		if error!=OK:data=original;return "Could not save the pending laptop purchase"
		return queued("buy_portable_laptop",[tier,hotbar_limit,id] if selected.is_empty() else [tier,hotbar_limit,id,selected])
	if dorm.get("portable_laptops",{}).size()>=laptops.MAX_LAPTOPS:return "Laptop limit reached"
	var carried: Array=dorm.get("carry_items",[])
	var hotbar: bool=carried.size()+dorm.get("carried_components",[]).size()<hotbar_limit
	if not hotbar and Dorm.storage_used(dorm)>=Dorm.CAPACITY:return "No room in your hotbar or dorm cabinet"
	var debit:=Economy.purchase_debit(int(data.dollars),price,true)
	if not debit.ok:return debit.error
	var before:=data.duplicate(true)
	if not dorm.has("portable_laptops"):dorm.portable_laptops={}
	dorm.portable_laptops[id]={"tier":tier,"location":"hotbar" if hotbar else "cabinet"}
	if not selected.is_empty():dorm.portable_laptops[id].configuration=selected
	if hotbar:dorm.carry_items=carried+["laptop:"+id]
	dorm.revision=int(dorm.revision)+1;data.dollars=debit.next_balance
	if save()!=OK:data=before;return "Laptop purchase could not be saved"
	operation_succeeded=true
	return "%s added to your %s" % [laptops.TIERS[tier].name if selected.is_empty() else "Custom laptop","hotbar" if hotbar else "dorm cabinet"]

func buy_smartphone(tier: String,hotbar_limit := 6,requested_id := "",configuration: Variant = {}) -> String:
	operation_succeeded=false
	if purchase_hotbar_limit.is_valid():hotbar_limit=mini(hotbar_limit,purchase_hotbar_limit.call())
	var tiers: Dictionary=preload("res://scripts/campus/phones/phone_tiers.gd").TIERS
	if not tiers.has(tier) or not data.has("dorm"):return "Phone unavailable"
	if not configuration is Dictionary:return "Invalid phone configuration"
	var price:=int(tiers[tier].price)
	var selected := {}
	if not configuration.is_empty():
		if tier!="basic":return "Configured phones use the standard chassis"
		var quote:=EquipmentConfiguration.quote(EquipmentConfiguration.PHONE,price,configuration)
		if quote.is_empty():return "Invalid phone configuration"
		price=int(quote.price)
		selected=quote.configuration
	if not data.get("pending_trade",{}).is_empty():return "Finish the pending trade first"
	var dorm: Dictionary=data.dorm
	var id:=requested_id if not requested_id.is_empty() else Crypto.new().generate_random_bytes(16).hex_encode()
	if id.length()!=32 or not id.is_valid_hex_number() or id!=id.to_lower() or dorm.get("smartphones",{}).has(id):return "Invalid phone identity"
	if authority_submit.is_valid():
		if data.get("phone_purchase_pending",{}).size()>=16:return "Too many phone purchases are awaiting confirmation"
		var authority: Object=authority_submit.get_object()
		var host: String=str(authority.get("bound_host")) if is_instance_valid(authority) else ""
		if host.is_empty():return "Host inventory is not ready"
		var original: Dictionary=data.duplicate(true)
		if not data.has("phone_purchase_pending"):data.phone_purchase_pending={}
		data.phone_purchase_pending[id]={"tier":tier,"host":host}
		if not selected.is_empty():data.phone_purchase_pending[id].configuration=selected
		var callback:=authority_submit;authority_submit=Callable()
		var error:=save();authority_submit=callback
		if error!=OK:data=original;return "Could not save the pending phone purchase"
		return queued("buy_smartphone",[tier,hotbar_limit,id] if selected.is_empty() else [tier,hotbar_limit,id,selected])
	if dorm.get("smartphones",{}).size()>=64:return "Phone limit reached"
	var carried: Array=dorm.get("carry_items",[])
	var hotbar: bool=carried.size()+dorm.get("carried_components",[]).size()<hotbar_limit
	if not hotbar and Dorm.storage_used(dorm)>=Dorm.CAPACITY:return "No room in your hotbar or dorm cabinet"
	var debit:=Economy.purchase_debit(int(data.dollars),price,true)
	if not debit.ok:return debit.error
	var before:=data.duplicate(true)
	if not dorm.has("smartphones"):dorm.smartphones={}
	dorm.smartphones[id]={"tier":tier,"location":"hotbar" if hotbar else "cabinet"}
	if not selected.is_empty():dorm.smartphones[id].configuration=selected
	if hotbar:dorm.carry_items=carried+["phone:"+id]
	dorm.revision=int(dorm.revision)+1;data.dollars=debit.next_balance
	if save()!=OK:data=before;return "Phone purchase could not be saved"
	operation_succeeded=true
	return "%s added to your %s"%[tiers[tier].name if selected.is_empty() else "Custom smartphone","hotbar" if hotbar else "dorm cabinet"]

func kit_capacity(id: String) -> int:
	var tier := str(data.get("kit_tiers",{}).get(id,""))
	return int(KIT_TIERS[tier].capacity) if KIT_TIERS.has(tier) else int(data.capacity)

func kit_used(id: String) -> int:
	var items: Dictionary = data.kits.get(id,{}).get("items",{})
	var cached: Dictionary = kit_usage_cache.get(id,{})
	if cached.get("items")==items:return int(cached.used)
	var used := 0
	var entries := catalog()
	for type in items:used+=int(items[type])*int(entries.get(type,{}).get("space",0))
	kit_usage_cache[id]={"items":items.duplicate(),"used":used}
	return used

func create_kit(tier: String, hotbar_limit := 6) -> String:
	if purchase_hotbar_limit.is_valid():hotbar_limit = mini(hotbar_limit,purchase_hotbar_limit.call())
	if authority_submit.is_valid():return queued("create_kit",[tier,hotbar_limit])
	operation_succeeded=false
	if not KIT_TIERS.has(tier):return "Unknown kit size"
	if not data.get("pending_trade",{}).is_empty():return "Finish the pending trade first"
	if data.kits.size()>=1000 or data.get("kit_tiers",{}).size()>=1000:return "Kit limit reached"
	var product: Dictionary = KIT_TIERS[tier]
	var debit := Economy.purchase_debit(int(data.dollars),int(product.price),true)
	if not debit.ok:return debit.error
	var before := data.duplicate(true)
	var id := Crypto.new().generate_random_bytes(12).hex_encode()
	var destination := "kit inventory"
	if data.has("dorm"):
		destination = Dorm.receive_purchase(data.dorm,"kit",id,hotbar_limit)
		if destination.is_empty():return "No room in your hotbar, backpack, or dorm cabinet"
		data.dorm.revision+=1
	else:data.equipped=id
	if not data.has("kit_tiers"):data.kit_tiers={}
	data.kit_tiers[id]=tier
	data.kits[id]={"name":str(product.name),"items":{},"board":Board.empty()}
	data.dollars=debit.next_balance
	if save()!=OK:data=before;return "Kit could not be saved"
	operation_succeeded=true
	return "%s added to your %s" % [product.name,destination]

func kit_error(id: String) -> String:
	if not data.kits.has(id):return "Kit not found"
	var used := 0;var catalog := catalog()
	for type in data.kits[id].items:
		var amount := int(data.kits[id].items[type])
		if not catalog.has(type) or amount<0 or amount>int(data.inventory.get(type,0)):return "Kit contains components you no longer own"
		used+=amount*int(catalog[type].space)
	return "Kit exceeds capacity" if used>kit_capacity(id) else ""
func kit_available(type: String) -> int:
	var used := Dorm.stock_used(data)
	return maxi(0, int(data.inventory.get(type, 0)) - int(used.get(type, 0)))

func remove_kit_board_components(id: String) -> String:
	operation_succeeded = false
	if authority_submit.is_valid():return queued("remove_kit_board_components",[id])
	if not data.kits.has(id):return "Kit not found"
	if not data.get("pending_trade",{}).is_empty():return "Finish the pending trade first"
	var stored: Dictionary = data.get("dorm",{}).get("stored_board",{}).get("design",{})
	if stored.get("authority_kit_id","") == id:return "Retrieve the breadboard from your cabinet first."
	var kit: Dictionary = data.kits[id]
	var previous: Dictionary = kit.board
	if previous.parts.is_empty():
		operation_succeeded = true
		return "The breadboard has no components."
	var cleared := previous.duplicate(true)
	cleared.parts = []
	for key in ["instance_ids","component_runtime","controls","io_controls","programs"]:
		cleared.erase(key)
	kit.board = cleared
	if save() != OK:
		kit.board = previous
		return "The breadboard could not be saved."
	operation_succeeded = true
	return "All breadboard components returned to the kit."

func set_quantity(type: String,amount: int) -> String:
	return set_kit_quantity(str(data.equipped),type,amount)

func set_kit_quantity(id: String,type: String,amount: int) -> String:
	operation_succeeded=false
	if authority_submit.is_valid():return queued("kit_quantity",[id,type,amount])
	if not data.kits.has(id) or not catalog().has(type) or not quantity(amount):return "Invalid kit component change"
	if not data.get("pending_trade",{}).is_empty():return "Finish the pending trade first"
	var kit: Dictionary=data.kits[id];var before: Dictionary=kit.items.duplicate()
	var old := int(before.get(type,0))
	if amount>old and amount-old>kit_available(type):return "No unallocated copies of this component"
	if amount<old and kit.board.parts.filter(func(part):return part.type==type).size()>amount:
		return "Remove this component from the breadboard first"
	if amount==0:kit.items.erase(type)
	else:kit.items[type]=amount
	var error := kit_error(id)
	if error!="" and amount>=old:kit.items=before;return error
	if save()!=OK:kit.items=before;return "Save failed"
	operation_succeeded=true
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
	if authority_submit.is_valid():return queued("duplicate_kit")
	operation_succeeded=false
	var before := data.duplicate(true);var id := Crypto.new().generate_random_bytes(12).hex_encode()
	var source := str(data.equipped)
	if not data.kits.has(source) or not data.get("pending_trade",{}).is_empty() or data.kits.size()>=1000:return "Kit copy unavailable"
	for type in data.kits[source].items:
		if int(data.kits[source].items[type])>kit_available(type):return "Free enough stock to copy this kit first."
	data.kits[id]=data.kits[source].duplicate(true);data.kits[id].name+=" copy";data.equipped=id
	data.kits[id].erase("workspace_only")
	data.kits[id].erase("package_draft")
	if data.get("kit_tiers",{}).has(source):
		data.kit_tiers[id]="standard"
		var error := kit_error(id)
		if not error.is_empty():
			data=before
			return "This kit cannot be copied into a free 40-space slot."
	var destination:="kit inventory"
	if data.has("dorm"):
		var hotbar_limit:=int(purchase_hotbar_limit.call()) if purchase_hotbar_limit.is_valid() else 6
		destination=Dorm.receive_purchase(data.dorm,"kit",id,hotbar_limit)
		if destination.is_empty():
			data=before
			return "No room in your hotbar, backpack, or dorm cabinet"
		data.dorm.revision=int(data.dorm.get("revision",0))+1
		if destination=="dorm cabinet":data.equipped=source
	if save()!=OK:data=before;return "Save failed"
	operation_succeeded=true
	return "Kit copy added to your "+destination
func delete_kit(id: String="") -> String:
	operation_succeeded=false
	var target:=id if not id.is_empty() else str(data.equipped)
	if authority_submit.is_valid():return queued("delete_kit",[target])
	if not data.kits.has(target):return "Kit not found"
	var dorm: Dictionary=data.get("dorm",{})
	if target in dorm.get("stored_kits",[]) or "kit:"+target in dorm.get("carry_items",[]):return "Put this kit away before deleting it"
	for item in preload("res://scripts/campus/dorms/authority/backpack_inventory.gd").entries(data.get("dorm",{}),"kit"):
		if item.id==target:return "Remove this kit from its backpack first"
	if data.kits.size()==1:return "Keep at least one kit"
	var before := data.duplicate(true);data.kits.erase(target)
	if str(data.equipped)==target:data.equipped=data.kits.keys()[0]
	if data.has("kit_tiers"):data.kit_tiers.erase(target)
	if save()!=OK:data=before;return "Save failed"
	operation_succeeded=true
	return "Kit deleted; owned components are unchanged"
func purchase_bundle(items: Dictionary,price: int) -> String:
	last_bundle_receipt = {}
	operation_succeeded=false
	if authority_submit.is_valid():return queued("bundle",[items])
	if not data.get("pending_trade",{}).is_empty():return "Finish the pending trade first"
	var debit := Economy.purchase_debit(data.dollars,price,true)
	if not debit.ok:return debit.error
	var before := data.duplicate(true)
	for id in items:
		if not Catalog.all().has(id) or not quantity(items[id],1000) or int(items[id])<1:return "Invalid bundle"
	var definition: Dictionary=preload("res://scripts/ui/store_bundles_equipment/bundle_catalog.gd").find(items)
	var tier := str(definition.get("kit_tier",""))
	if not tier.is_empty():
		if data.kits.size()>=1000 or data.get("kit_tiers",{}).size()>=1000:return "Kit limit reached"
		var capacity_used := 0
		for id in items:capacity_used+=int(Catalog.all()[id].space)*int(items[id])
		if capacity_used>int(KIT_TIERS[tier].capacity):return "Bundle exceeds kit capacity"
		var kit_id := Crypto.new().generate_random_bytes(12).hex_encode()
		if data.has("dorm"):
			var hotbar_limit := int(purchase_hotbar_limit.call()) if purchase_hotbar_limit.is_valid() else 6
			if Dorm.receive_purchase(data.dorm,"kit",kit_id,hotbar_limit).is_empty():return "No room in your hotbar, backpack, or dorm cabinet"
			data.dorm.revision+=1
		else:data.equipped=kit_id
		if not data.has("kit_tiers"):data.kit_tiers={}
		data.kit_tiers[kit_id]=tier
		data.kits[kit_id]={"name":str(definition.name),"items":items.duplicate(true),"board":Board.empty()}
	for id in items:data.inventory[id]=int(data.inventory.get(id,0))+int(items[id])
	data.dollars=debit.next_balance
	if save()!=OK:data=before;return "Save failed; purchase rolled back"
	operation_succeeded=true
	last_bundle_receipt = items.duplicate(true)
	return "Bundle purchased"

func catalog() -> Dictionary:
	var result := preload("res://scripts/electronics/component_values/values.gd").augment(preload("res://scripts/custom_circuit.gd").catalog(data.get("blueprints",{})),data.get("inventory",{}).keys())
	for id in data.get("ic_library", {}):
		if not result.has(id): continue
		var entry: Dictionary = data.ic_library[id]
		if not str(entry.get("name", "")).is_empty(): result[id].name = entry.name
		result[id].archived = entry.get("archived", false)
	return result
func save_blueprint(title: String,pin_map: Array=[],description: String="",package: String="IC",width: int=8,height: int=6,color: String="24775b",exposed: Array=[],metadata: Dictionary={}) -> String:
	var before := data.duplicate(true);var design: Dictionary=data.kits[data.equipped].board
	if Board.Debug.contains(design):return "Remove simulation instruments before building an IC or PCB."
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
		if design.get("expanded",false):blueprint.layout.expanded=true
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
	var error: String=Custom.manufacturing_error(id,definitions)
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
	mark_manufactured(id)
	if save()!=OK:data=before;return "Save failed; transaction rolled back"
	operation_succeeded=true
	return "Custom IC added to inventory"

func fabricate_invention(id: String) -> String:
	operation_succeeded=false
	# Profile validation caps each fabricated design at 100 copies. Reject
	# before spending and saving, rather than reporting a generic save error.
	if int(data.get("invention_copies",{}).get(id,0))>=100:
		return "Maximum 100 fabricated copies per invention. Discard unused copies before fabricating more."
	if authority_submit.is_valid():return queued("invention_fabricate",[id])
	var designs: Dictionary=data.get("inventions",{})
	var assembly=preload("res://scripts/campus/facilities/circuit_studio/assembly_model.gd")
	var structure_error: String=assembly.structure_error(id,designs,data.get("blueprints",{}))
	if not structure_error.is_empty():return structure_error
	var cost: int=assembly.price(id,designs,data.get("blueprints",{}))
	if cost<0:return "Invalid invention blueprint"
	var debit:=Economy.purchase_debit(data.dollars,cost,true)
	if not debit.ok:return str(debit.error)
	var before: Dictionary=data.duplicate(true)
	data.dollars=debit.next_balance
	if not data.has("invention_copies"):data.invention_copies={}
	data.invention_copies[id]=int(data.invention_copies.get(id,0))+1
	if save()!=OK:
		data=before
		return "Could not save fabricated invention"
	operation_succeeded=true
	return "Invention copy fabricated"

func mark_manufactured(id: String) -> void:
	if not data.has("ic_library"): data.ic_library = {}
	if not data.ic_library.has(id): data.ic_library[id] = {}
	data.ic_library[id].manufactured = true

func upgrade_ic(old: String, id: String, proposal: Dictionary, mode: String, creative := false, deployment: Dictionary = {}) -> String:
	operation_succeeded = false
	upgraded_board = {}
	upgraded_boards = {}
	if authority_submit.is_valid(): return queued("ic_upgrade",[old,id,proposal,mode])
	var reserved := Dorm.stock_used(data,deployment)
	var result := preload("res://scripts/electronics/ic_pcb_editor/upgrade.gd").transact(data,old,id,proposal,reserved,deployment,mode,creative)
	if not result.error.is_empty(): return result.error
	var before := data
	data = result.profile
	if save() != OK:
		data = before
		return "Could not save the upgrade transaction."
	operation_succeeded = true
	upgraded_board = result.get("board",{})
	upgraded_boards = result.get("boards",{})
	return result.message

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
		if int(payload.give[type])>kit_available(type):return "Unpack or retrieve components before trading"
	if not Persistent.registry(payload.get("give_instances",{}),payload.give) or not Persistent.registry(payload.get("take_instances",{}),payload.take):return "Invalid persistent component instances"
	for instance in payload.get("give_instances",{}):
		if instance in data.get("dorm",{}).get("instances",[]) or instance in Dorm.packed_instance_ids(data):return "Unpack or retrieve the instance before trading"
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
	last_bundle_receipt = {}
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
	last_bundle_receipt = won.duplicate(true)
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
	if authority_revision < 0 and not same(data.get("inventory", {}), snapshot.profile.get("inventory", {})):
		return ERR_BUSY
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
	# Unrelated host snapshots can arrive while a locally staged USB operation
	# is in flight. Keep its recovery marker until the matching item or receipt
	# is present in an authoritative snapshot.
	for id in before.get("usb_purchase_pending",{}):
		if not data.get("dorm",{}).get("usb_drives",{}).has(id) and not data.get("usb_purchase_resolved",{}).has(id):
			if not data.has("usb_purchase_pending"):data.usb_purchase_pending={}
			data.usb_purchase_pending[id]=before.usb_purchase_pending[id]
	for id in before.get("laptop_purchase_pending",{}):
		if not data.get("dorm",{}).get("portable_laptops",{}).has(id) and not data.get("laptop_purchase_resolved",{}).has(id):
			if not data.has("laptop_purchase_pending"):data.laptop_purchase_pending={}
			data.laptop_purchase_pending[id]=before.laptop_purchase_pending[id].duplicate(true)
	for id in before.get("phone_purchase_pending",{}):
		if not data.get("dorm",{}).get("smartphones",{}).has(id) and not data.get("phone_purchase_resolved",{}).has(id):
			if not data.has("phone_purchase_pending"):data.phone_purchase_pending={}
			data.phone_purchase_pending[id]=before.phone_purchase_pending[id].duplicate(true)
	for token in before.get("usb_write_pending",{}):
		var pending: Dictionary=before.usb_write_pending[token]
		if not data.get("usb_write_decisions",{}).has(token):
			if not data.has("usb_write_pending"):data.usb_write_pending={}
			data.usb_write_pending[token]=pending.duplicate(true)
			continue
		if bool(data.usb_write_decisions[token]):
			var archive=preload("res://scripts/campus/computers/usb_archive.gd")
			var staged: Dictionary=archive.load(str(data.dorm.owner),str(token),int(pending.capacity))
			if staged.has("error") or archive.save(str(data.dorm.owner),str(pending.id),str(staged.get("name","")),int(pending.capacity),staged.get("drive"))!=OK:
				data=before;return ERR_FILE_CANT_WRITE
			if not data.has("usb_write_completed"):data.usb_write_completed={}
			data.usb_write_completed[token]=true
		data.get("usb_write_pending",{}).erase(token)
	for token in before.get("usb_write_completed",{}):
		if not data.has("usb_write_completed"):data.usb_write_completed={}
		data.usb_write_completed[token]=true
	for id in before.get("usb_received_pending",{}):
		var pending: Dictionary=before.usb_received_pending[id]
		if data.get("usb_delivery_receipts",{}).get(id,"")!=pending.token:
			if not data.has("usb_received_pending"):data.usb_received_pending={}
			data.usb_received_pending[id]=pending.duplicate(true)
	authority_revision=int(snapshot.revision)
	var callback := authority_submit;authority_submit=Callable()
	var error := save();authority_submit=callback
	if error!=OK:data=before;authority_revision=revision_before
	return error
