extends RefCounted
const Dorm=preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
const Profile=preload("res://scripts/electronics_profile.gd")
const Board=preload("res://scripts/breadboard_model.gd")
const Custom=preload("res://scripts/custom_circuit.gd")
const Persistent=preload("res://scripts/inventory_authority/component_persistence.gd")
const Store=preload("res://scripts/inventory_authority/store.gd")
const ReceiptHistory=preload("res://scripts/inventory_authority/receipt_archive/coordinator.gd")
const AvatarCoordinator=preload("res://scripts/avatar_cosmetics/core/coordinator.gd")
var receipt_history=ReceiptHistory.new()
var store=Store.new()
var state := {"schema":1,"accounts":{},"transactions":{}}
var bindings := {}
var creative := false
func open(path: String) -> Error:
	bindings.clear()
	var error: Error=store.open(path)
	if error!=OK:return error
	var opened: Dictionary=receipt_history.open_store(store)
	if not opened.ok:return ERR_FILE_CORRUPT
	state=opened.state
	return OK
func persist(next: Dictionary) -> bool:
	var prepared: Dictionary=receipt_history.prepare(next)
	if not prepared.ok:return false
	if store.commit(prepared.state)!=OK:return false
	state=prepared.state;return true
func receipt_delivery_hints(journal: Dictionary) -> bool:
	return receipt_history.delivery_hints(state,journal)
func bind(peer: int,identity: String,secret: String,initial: Dictionary) -> Dictionary:
	if identity.length()!=48 or not identity.is_valid_hex_number() or secret.length()!=64 or not secret.is_valid_hex_number():return failure("Invalid profile credential")
	if bindings.has(peer) and bindings[peer]!=identity:return failure("Peer is already bound")
	for token in state.accounts:
		if token!=identity and state.accounts[token].credential==secret.sha256_text():return failure("Credential already belongs to another profile")
	for other in bindings:
		if other!=peer and bindings[other]==identity:return failure("Profile is already connected")
	if state.accounts.has(identity):
		if state.accounts[identity].credential!=secret.sha256_text():return failure("Profile credential mismatch")
		if not bindings.has(peer):
			if var_to_bytes(initial).size()>1048576 or not Profile.valid(initial) or not initial.get("pending_trade",{}).is_empty():return failure("Invalid local profile or unresolved legacy trade")
			if not state.accounts[identity].deployment.is_empty():return failure("Previous deployed inventory is still being recovered")
			var imported := initial.duplicate(true)
			imported.erase("authority_credentials")
			var migrated: Dictionary=Dorm.migrate(imported,identity)
			if not migrated.ok:return failure(migrated.error)
			imported=migrated.profile
			if not Profile.same(imported,state.accounts[identity].profile):
				var next := state.duplicate(true)
				next.accounts[identity].profile=imported;next.accounts[identity].revision+=1
				if not persist(next):return failure("Host inventory save failed")
	else:
		# Local saves are explicitly trusted ONCE, never accepted as subsequent stock reports.
		if var_to_bytes(initial).size()>1048576 or not Profile.valid(initial) or not initial.get("pending_trade",{}).is_empty():return failure("Invalid initial profile or unresolved legacy trade")
		var imported := initial.duplicate(true);imported.erase("authority_credentials")
		var migrated: Dictionary=Dorm.migrate(imported,identity)
		if not migrated.ok:return failure(migrated.error)
		imported=migrated.profile
		var next := state.duplicate(true)
		next.accounts[identity]={"credential":secret.sha256_text(),"profile":imported,"revision":0,"receipts":{},"deployment":{}}
		if not persist(next):return failure("Host save failed")
	var migration: Dictionary=Dorm.migrate(state.accounts[identity].profile,identity)
	if not migration.ok:return failure(migration.error)
	if migration.changed:
		var next := state.duplicate(true)
		next.accounts[identity].profile=migration.profile;next.accounts[identity].revision+=1
		if not persist(next):return failure("Dorm enrollment save failed")
	bindings[peer]=identity
	return snapshot(peer)
static func _sync_upgraded_templates(profile: Dictionary) -> void:
	var upgrades: Dictionary = profile.get("ic_upgrades",{})
	if upgrades.is_empty(): return
	var logic := preload("res://scripts/electronics/ic_pcb_editor/upgrade.gd")
	for kit in profile.kits.values():
		for id in upgrades:
			if not kit.items.has(id): continue
			var revision: String = upgrades[id]
			kit.items[revision] = int(kit.items.get(revision,0))+int(kit.items[id])
			kit.items.erase(id)
		kit.board = logic.resolve_board(profile,kit.board)

func unbind(peer: int) -> void:bindings.erase(peer)
func failure(message: String) -> Dictionary:return {"ok":false,"error":message}
func snapshot(peer: int) -> Dictionary:
	if not bindings.has(peer):return failure("Profile is not bound")
	var account: Dictionary=state.accounts[bindings[peer]]
	return {"ok":true,"revision":account.revision,"profile":account.profile.duplicate(true),"economy":preload("res://scripts/economy/temporary_playtest/policy.gd").display_snapshot(true)}
func account(peer: int) -> Dictionary:return state.accounts.get(bindings.get(peer,""),{})
func free_stock(peer: int,type: String) -> int:
	var a := account(peer)
	var profile: Dictionary=a.get("profile",{})
	return maxi(0,int(profile.get("inventory",{}).get(type,0))-int(Dorm.stock_used(profile,a.get("deployment",{})).get(type,0)))
func offer_error(peer: int,items: Variant,definitions: Variant) -> String:
	if creative:return "Creative components cannot be traded"
	if account(peer).is_empty():return "Profile is not bound"
	if not items is Dictionary or items.size()>64 or not definitions is Dictionary:return "Invalid offer"
	var owned: Dictionary=account(peer).profile.get("blueprints",{})
	for id in definitions:
		if not owned.has(id) or not Profile.same(owned[id],definitions[id]):return "Blueprint does not match host library"
	for type in items:
		if not Profile.quantity(items[type]) or int(items[type])>free_stock(peer,str(type)):return "Offer exceeds available master stock"
		if not preload("res://scripts/electronics/component_values/values.gd").augment(Custom.catalog(owned),[type]).has(type):return "Unknown component"
		if str(type).begins_with("ic:") and Custom.validate(type,owned)!="":return "Invalid custom circuit dependencies"
	return ""
func transact(peer: int,id: String,op: String,args: Array,live_design: Dictionary = {},live_boards: Dictionary = {}) -> Dictionary:
	if account(peer).is_empty():return failure("Profile is not bound")
	if id.is_empty() or id.length()>96 or var_to_bytes(args).size()>1048576:return failure("Invalid request")
	var a := account(peer)
	var digest := var_to_bytes([op,args]).hex_encode().sha256_text()
	var prior: Dictionary=receipt_history.lookup_op(state,bindings[peer],id)
	if not prior.ok:return failure("Receipt history unavailable; request blocked")
	if prior.found:
		if prior.value!=digest:return failure("Transaction ID reused with different content")
		return _transaction_snapshot(peer, id)
	var p=Profile.new();p.data=a.profile.duplicate(true)
	p.craft_reservations=func():return {"counts":Dorm.reserved(a.profile,a.deployment),"instance_ids":a.deployment.get("instance_ids",[])+a.profile.get("dorm",{}).get("instances",[])}
	var message := ""
	var bundle_name := ""
	var deployment: Dictionary = a.deployment.duplicate(true)
	match op:
		"create_kit":
			if args.size() not in [1,2] or not args[0] is String or (args.size()==2 and (not args[1] is int or args[1] not in range(7))):return failure("Invalid kit size")
			message=p.create_kit(args[0],args[1] if args.size()==2 else 6)
			if not p.operation_succeeded:return failure(message)
		"duplicate_kit":
			if not args.is_empty():return failure("Invalid kit copy")
			message=p.duplicate_kit()
			if not p.operation_succeeded:return failure(message)
		"remove_kit_board_components":
			if args.size()!=1 or not args[0] is String:return failure("Invalid kit")
			for record in deployment_slots(deployment).values():
				if record.get("kit","")==args[0]:return failure("Put the breadboard back in its kit first.")
			message=p.remove_kit_board_components(args[0])
			if not p.operation_succeeded:return failure(message)
		"study_tool":
			if args.size() not in [1,2] or not args[0] is String or (args.size()==2 and (not args[1] is int or args[1] not in range(7))):return failure("Invalid study supply")
			message=p.buy_study_tool(args[0],args[1] if args.size()==2 else 6)
			if not p.operation_succeeded:return failure(message)
		"dorm":
			if args.size()!=1 or not args[0] is Dictionary:return failure("Invalid dorm intent")
			var result: Dictionary=Dorm.apply_intent(p.data,str(bindings[peer]),args[0],a.deployment)
			if not result.ok:return failure(result.error)
			p.data=result.profile;message="Dorm saved"
		"avatar_cosmetic","cosmetic_purchase":
			if args.size()!=1 or not args[0] is Dictionary:return failure("Invalid cosmetic request")
			var intent: Dictionary=args[0]
			if intent.get("op") not in ["purchase","equip","unequip","body","edit"]:return failure("Unsupported cosmetic intent")
			if op=="cosmetic_purchase" and intent.get("op")!="purchase":return failure("Invalid store intent")
			var cosmetics := AvatarCoordinator.new()
			if not cosmetics.load_catalog():return failure("Cosmetic catalog unavailable")
			var adapter = cosmetics.authoritative_adapter(func():return true)
			var result: Dictionary=adapter.apply_authoritative(p.data,intent)
			if not result.ok:return failure(result.get("error","Cosmetic request failed"))
			p.data=result.profile
			p.operation_succeeded=true
			message="Appearance saved" if intent.op!="purchase" else "Cosmetic purchased"
		"buy_configured":
			if args.size()!=3 or not args[0] is String:return failure("Invalid configured purchase")
			message=p.buy_configured(args[0],args[1],args[2],true)
		"buy":
			if args.size()!=2 or not args[0] is String or not Profile.quantity(args[1],100):return failure("Invalid purchase")
			message=p.buy(args[0],int(args[1]))
		"sell_component":
			if args.size()!=1 or not args[0] is String:return failure("Invalid sale")
			message=p.sell_component(args[0])
			if not p.operation_succeeded:return failure(message)
		"analyzer":message=p.buy_analyzer()
		"box":
			if args.size()!=1 or not args[0] is String:return failure("Invalid box")
			message=p.buy_box(args[0])
			bundle_name = args[0]
		"cosmetic":
			if args.size()!=1 or not args[0] is String:return failure("Invalid cosmetic")
			message=p.buy_cosmetic(args[0])
		"ic_upgrade":
			if args.size()!=4 or not args[0] is String or not args[1] is String or not args[2] is Dictionary or args[3] not in ["apply","purchase"]: return failure("Invalid IC upgrade request")
			var context := deployment.duplicate()
			context.board = live_design
			context.boards = live_boards
			message=p.upgrade_ic(args[0],args[1],args[2],args[3],creative,context)
			if not p.upgraded_board.is_empty():
				deployment.counts = {}
				for part in p.upgraded_board.parts:
					deployment.counts[part.type] = int(deployment.counts.get(part.type,0))+1
				deployment.instance_ids = p.upgraded_board.get("instance_ids",{}).values()
			if not live_boards.is_empty() and not p.upgraded_boards.is_empty():
				var slots := deployment_slots(deployment)
				for slot in p.upgraded_boards:
					var record: Dictionary=slots.get(str(slot),{})
					if record.is_empty():return failure("The deployed circuit changed during the update.")
					var updated: Dictionary=p.upgraded_boards[slot]
					record.counts={}
					for part in updated.parts:record.counts[part.type]=int(record.counts.get(part.type,0))+1
					record.instance_ids=updated.get("instance_ids",{}).values()
				deployment=summarize_slots(slots)
		"obtain":
			if args.size()!=2 or not args[0] is String or not args[1] is bool:return failure("Invalid crafting request")
			message=p.obtain_ic(args[0],args[1])
		"capacity":
			var debit := preload("res://scripts/economy/temporary_playtest/policy.gd").purchase_debit(p.data.dollars,50,true)
			if not debit.ok or p.data.capacity>99980:return failure("Capacity upgrade unavailable")
			p.data.dollars=debit.next_balance;p.data.capacity+=20
		"bundle":
			# Price is derived by the server, never from a client supplied number.
			if args.size()!=1 or not args[0] is Dictionary:return failure("Invalid bundle")
			var matched := false
			for bundle in [{"name":"Resistor box","items":{"r1000":10,"r220":10,"r10000":10}},{"name":"Capacitor box","items":{"c0.1":4,"c1.0":4,"c10.0":4}},{"name":"Semiconductor starter","items":{"diode":6,"led":6}}]:
				if bundle.items==args[0]:
					var cost := 0
					for type in bundle.items:cost+=int(preload("res://scripts/electronics_catalog.gd").all()[type].price)*int(bundle.items[type])
					bundle_name = bundle.name
					message=p.purchase_bundle(bundle.items,maxi(1,ceili(cost*.8)));matched=true;break
			if not matched:return failure("Unknown bundle")
		"metadata":
			if args.size()!=1 or not args[0] is Dictionary:return failure("Invalid metadata")
			var incoming: Dictionary=args[0]
			for key in ["kits","equipped","circuit_draft","notebook","notebook_pages","notebook_page","blueprints","programs","favorites","ic_library"]:
				if incoming.has(key):p.data[key]=incoming[key].duplicate(true) if incoming[key] is Dictionary or incoming[key] is Array else incoming[key]
			# Validate untrusted field types before dereferencing the blueprint library.
			if not Profile.valid(p.data):return failure("Invalid profile metadata")
			# Existing blueprint identities are immutable; edits use new IDs.
			for key in a.profile.get("blueprints",{}):
				if not Profile.same(p.data.get("blueprints",{}).get(key),a.profile.blueprints[key]):return failure("Blueprint identity conflict")
			_sync_upgraded_templates(p.data)
			for key in a.profile.get("ic_library",{}):
				if a.profile.ic_library[key].get("manufactured",false): p.mark_manufactured(key)
			if not Profile.valid(p.data):return failure("Invalid profile metadata")
		_ :return failure("Unsupported client operation")
	if op in ["buy_configured","buy","analyzer","box","cosmetic","obtain","bundle","avatar_cosmetic","cosmetic_purchase","ic_upgrade"] and not p.operation_succeeded:return failure(message)
	if not Profile.valid(p.data):return failure("Invalid resulting profile")
	if Dorm.adds_stock_shortage(a.profile,p.data,deployment):return failure("Some components are already packed, stored or deployed")
	var reservations: Dictionary=Dorm.reserved(p.data,deployment)
	for type in reservations:
		if int(p.data.inventory.get(type,0))<int(reservations[type]):return failure("Recall deployed or stored components first")
	var next := state.duplicate(true);var target: Dictionary=next.accounts[bindings[peer]]
	for kit in p.data.kits.values():
			if not kit.board.get("component_runtime",{}).is_empty():kit.board=Persistent.materialize(p.data,kit.board)
	target.profile=p.data;target.deployment=deployment;target.revision+=1;target.receipts[id]=digest
	if not p.last_bundle_receipt.is_empty():
		target.last_bundle = {"id":id,"name":bundle_name,"items":p.last_bundle_receipt}
	if not persist(next):return failure("Host save failed; request can be retried")
	var result := _transaction_snapshot(peer, id)
	result.message = message
	if not p.upgraded_board.is_empty(): result.upgraded_board = p.upgraded_board
	if not live_boards.is_empty() and not p.upgraded_boards.is_empty():result.upgraded_boards=p.upgraded_boards
	return result
func _transaction_snapshot(peer: int, id: String) -> Dictionary:
	var result := snapshot(peer)
	var receipt: Dictionary = account(peer).get("last_bundle", {})
	if receipt.get("id", "") == id:
		result.bundle_receipt = receipt.duplicate(true)
	return result

func award(peer: int,id: String,grade: float,difficulty: int,lesson: bool) -> Dictionary:
	# Only called by the host's grading code; deliberately absent from client dispatch.
	if creative or account(peer).is_empty():return failure("Reward unavailable")
	if not receipt_history.verify(state).ok:return failure("Receipt history unavailable; reward blocked")
	var p=Profile.new();p.data=account(peer).profile.duplicate(true)
	var earned: int=p.reward(id,grade,difficulty,lesson)
	var next := state.duplicate(true);next.accounts[bindings[peer]].profile=p.data;next.accounts[bindings[peer]].revision+=1
	if not persist(next):return failure("Host reward save failed")
	var result := snapshot(peer);result.earned=earned;return result
static func deployment_slots(deployment: Dictionary) -> Dictionary:
	if deployment.has("slots"):return deployment.slots.duplicate(true)
	if deployment.has("slot"):return {str(deployment.slot):deployment.duplicate(true)}
	return {}

static func summarize_slots(slots: Dictionary) -> Dictionary:
	if slots.is_empty():return {}
	if slots.size()==1:return slots.values()[0]
	var result := {"slots":slots,"counts":{},"instance_ids":[]}
	for record in slots.values():
		for type in record.counts:
			result.counts[type]=int(result.counts.get(type,0))+int(record.counts[type])
		result.instance_ids.append_array(record.instance_ids)
	return result

func deployment_error(peer: int,design: Dictionary) -> String:
	if var_to_bytes(design).size()>1048576 or not preload("res://scripts/inventory_authority/validation.gd").board(design):return "Invalid board data"
	if account(peer).is_empty():return "Profile is not bound"
	var p=Profile.new();p.data=account(peer).profile
	var kit_id := str(design.get("authority_kit_id",p.data.equipped))
	if not p.data.kits.has(kit_id):return "Kit not found"
	if not creative:
		var error: String=p.kit_error(kit_id)
		if error!="":return error
		for id in design.get("definitions",{}):
			if not Profile.same(p.data.get("blueprints",{}).get(id),design.definitions[id]):return "Blueprint does not match host library"
	return Board.validate(design,p.data.kits[kit_id].items,creative)

func deploy(peer: int,slot: int,design: Dictionary,counter_pcb := false) -> String:
	var error := Board.validate(design, {}, true) if counter_pcb else deployment_error(peer,design)
	if error!="":return error
	var owned := account(peer)
	if owned.is_empty():return "Profile is not bound"
	var kit := "" if counter_pcb else str(design.get("authority_kit_id",owned.profile.equipped))
	var slots := deployment_slots(owned.deployment)
	slots.erase(str(slot))
	var instances: Array=design.get("instance_ids",{}).values()
	for other in slots.values():
		if not kit.is_empty() and other.kit==kit:return "That kit already has a breadboard out"
		for instance in instances:
			if instance in other.instance_ids:return "A selected component is already on another board"
	for instance in instances:
		if instance in owned.profile.get("dorm",{}).get("instances",[]):return "Retrieve stored instance first"
	var counts := {}
	if not creative or counter_pcb:
		for part in design.parts:counts[part.type]=int(counts.get(part.type,0))+1
	slots[str(slot)]={"slot":slot,"counts":counts,"kit":kit,"instance_ids":instances}
	var deployment := summarize_slots(slots)
	var reserved := Dorm.reserved(owned.profile,deployment)
	for type in reserved:
		if int(reserved[type])>int(owned.profile.inventory.get(type,0)):return "Retrieve stored components first"
	var next := state.duplicate(true)
	next.accounts[bindings[peer]].deployment=deployment
	return "" if persist(next) else "Host deployment save failed"

func recall(peer: int, slot: int = -1) -> bool:
	var owned := account(peer)
	if owned.is_empty():return false
	var slots := deployment_slots(owned.deployment)
	if slot<0:slots.clear()
	else:slots.erase(str(slot))
	var next := state.duplicate(true)
	next.accounts[bindings[peer]].deployment=summarize_slots(slots)
	return persist(next)

func transfer_cabinet_board(peer: int, slot: int, design: Dictionary) -> Dictionary:
	var owned := account(peer)
	if owned.is_empty():return failure("Profile is not bound")
	var deploying := design.is_empty()
	var slots := deployment_slots(owned.deployment)
	var record: Dictionary=slots.get(str(slot),{})
	if deploying and not record.is_empty():return failure("Board slot is in use")
	if not deploying and record.is_empty():return failure("Board is not owned at this station")
	var moved := Dorm.move_board(owned.profile,design,record.get("counts",{}))
	if not moved.ok:return failure(str(moved.error))
	var next := state.duplicate(true)
	var account_next: Dictionary = next.accounts[bindings[peer]]
	account_next.profile=moved.profile
	account_next.revision+=1
	slots.erase(str(slot))
	if deploying:
		var saved: Dictionary = moved.board
		var kit_id := str(saved.design.get("authority_kit_id",owned.profile.equipped))
		for other in slots.values():
			if kit_id!="" and other.kit==kit_id:return failure("That kit already has a breadboard out")
		slots[str(slot)]={"slot":slot,"counts":saved.counts,"kit":kit_id,"instance_ids":saved.instances}
	account_next.deployment=summarize_slots(slots)
	if not Profile.valid(account_next.profile) or not persist(next):return failure("Host cabinet save failed")
	return {"ok":true,"design":moved.board.get("design",{})}

func reset_world() -> bool:
	var next := state.duplicate(true)
	for a in next.accounts.values():a.deployment={}
	return persist(next)
func exchange(id: String,peers: Array,offers: Dictionary,definitions: Dictionary,choices: Dictionary={}) -> Dictionary:
	if id.is_empty() or id.length()>96:return failure("Invalid transaction ID")
	if peers.size()!=2 or peers[0]==peers[1] or not bindings.has(peers[0]) or not bindings.has(peers[1]):return failure("Invalid participants")
	if var_to_bytes([offers,definitions,choices]).size()>1048576:return failure("Invalid trade request")
	# Bind replay to authenticated identities, preserving peer-number changes.
	var request := {"offers":{},"choices":{},"definitions":definitions.duplicate(true)}
	for peer in peers:
		request.offers[bindings[peer]]=offers.get(peer)
		if choices.has(peer):request.choices[bindings[peer]]=choices[peer]
	var prior: Dictionary=receipt_history.lookup_trade(state,id)
	if not prior.ok:return failure("Receipt history unavailable; trade blocked")
	if prior.found:
		var saved: Dictionary=prior.value
		if not saved.has("request") or not Profile.same(saved.request,request):return failure("Trade ID reused with different or unverifiable content")
		var delivery := saved.duplicate(true);delivery.erase("request")
		return delivery
	var required := {}
	for peer in peers:
		var error := offer_error(peer,offers.get(peer),{})
		if error!="":return failure(error)
		for type in offers[peer]:
			if str(type).begins_with("ic:") and int(offers[peer][type])>0:
				error=dependencies(str(type),account(peer).profile.get("blueprints",{}),required)
				if error!="":return failure(error)
	# Only host-owned transitive definitions are transferred. Client extras cannot
	# introduce or overwrite unrelated designs, source code or firmware.
	for type in required:
		if definitions.has(type) and not Profile.same(definitions[type],required[type]):return failure("Blueprint identity conflict")
	var next := state.duplicate(true);var deliveries := {};var instances := {}
	for peer in peers:
		var source := account(peer);var excluded: Array=source.deployment.get("instance_ids",[]).duplicate();excluded.append_array(source.profile.get("dorm",{}).get("instances",[]))
		for instance in Dorm.packed_instance_ids(source.profile):
			if instance not in excluded:excluded.append(instance)
		instances[peer]=Persistent.selected(source.profile,offers[peer],excluded)
		if choices.has(peer):
			instances[peer]={};var selected_counts := {};var registry: Dictionary=source.profile.get("component_instances",{})
			if not choices[peer] is Dictionary:return failure("Invalid reviewed instances")
			for instance in choices[peer]:
				if not registry.has(instance) or instance in excluded:return failure("Reviewed instance is no longer available")
				var item: Dictionary=registry[instance]
				if instance_hash(item)!=choices[peer][instance]:return failure("Reviewed instance state changed")
				instances[peer][instance]=item.duplicate(true);selected_counts[item.type]=int(selected_counts.get(item.type,0))+1
			for type in offers[peer]:
				var generic := free_stock(peer,str(type))
				for instance in registry:
					if registry[instance].type==type and instance not in excluded:generic-=1
				var chosen := int(selected_counts.get(type,0))
				if chosen>int(offers[peer][type]) or int(offers[peer][type])-chosen>generic:return failure("Reviewed component instances changed")
			for type in selected_counts:
				if not offers[peer].has(type):return failure("Reviewed instance is not in the offer")
	for peer in peers:
		var other: int=peers[1] if peer==peers[0] else peers[0]
		var target: Dictionary=next.accounts[bindings[peer]]
		var p=Profile.new();p.data=target.profile
		var library: Dictionary=p.data.get("blueprints",{}).duplicate(true)
		for type in required:
			if library.has(type) and not Profile.same(library[type],required[type]):return failure("Blueprint identity conflict")
			library[type]=required[type].duplicate(true)
		p.data.blueprints=library
		for type in offers[peer]:p.data.inventory[type]=int(p.data.inventory.get(type,0))-int(offers[peer][type])
		for type in offers[other]:p.data.inventory[type]=int(p.data.inventory.get(type,0))+int(offers[other][type])
		var owned: Dictionary=p.data.get("component_instances",{}).duplicate(true)
		for instance in instances[peer]:owned.erase(instance)
		for instance in instances[other]:
			if owned.has(instance):return failure("Persistent instance identity conflict")
			owned[instance]=instances[other][instance].duplicate(true)
		p.data.component_instances=owned
		if not p.data.has("applied_trades"):p.data.applied_trades={}
		p.data.applied_trades[id]=true
		if not Profile.valid(p.data):return failure("Trade exceeds profile persistence limits")
		target.profile=p.data;target.revision+=1
		deliveries[bindings[peer]]={"revision":target.revision,"profile":p.data.duplicate(true)}
	var receipt := {"ok":true,"deliveries":deliveries}
	next.transactions[id]=receipt.duplicate(true)
	next.transactions[id].request=request
	return receipt if persist(next) else failure("Host transaction save failed")
func dependencies(id: String,owned: Dictionary,result: Dictionary) -> String:
	if result.has(id):return "" if Profile.same(result[id],owned[id]) else "Blueprint identity conflict"
	result[id]=owned[id].duplicate(true)
	for part in owned[id].parts:
		if str(part.type).begins_with("ic:"):
			var error := dependencies(str(part.type),owned,result)
			if error!="":return error
	return ""
func instance_hash(item: Dictionary) -> String:return var_to_bytes(item).hex_encode().sha256_text()

func materialize(peer: int,design: Dictionary,slot: int = -1) -> Dictionary:
	var owned := account(peer)
	var p: Dictionary=owned.get("profile",{})
	var kit_id := str(design.get("authority_kit_id",p.get("equipped","")))
	var unavailable := Dorm.packed_instance_ids(p,kit_id)
	unavailable.append_array(p.get("dorm",{}).get("instances",[]))
	for record in deployment_slots(owned.get("deployment",{})).values():
		if int(record.slot)!=slot:unavailable.append_array(record.instance_ids)
	if not creative and not p.is_empty():
		var next: Dictionary=state.duplicate(true)
		var target: Dictionary=next.accounts[bindings[peer]]
		if preload("res://scripts/physical_resistors.gd").ensure(target.profile,design,unavailable):
			target.revision+=1
			if not Profile.valid(target.profile) or not persist(next):return {}
			p=account(peer).profile
	var result := Persistent.materialize(p,design,unavailable)
	result.authority_kit_id=str(design.get("authority_kit_id",p.get("equipped","")))
	if creative and not p.is_empty():
		result.component_runtime=p.kits.get(kit_id,{}).get("board",{}).get("component_runtime",{}).duplicate(true)
		result.instance_ids={}
	return result
func capture_components(peer: int,board: Dictionary,states: Dictionary,slot: int = -1) -> String:
	if account(peer).is_empty():return "Profile is not bound"
	var next := state.duplicate(true);var target: Dictionary=next.accounts[bindings[peer]]
	var copy := board.duplicate(true)
	var error := ""
	if creative and board.get("authority_kit_id", "existing_kit") != "":
		copy.component_runtime=Persistent.capture(states);copy.instance_ids={}
		if not Persistent.valid(copy.component_runtime):error="Nonvolatile component state exceeds persistence limits"
	else:error=Persistent.retain(target.profile,copy,states)
	if error!="":return error
	var slots := deployment_slots(target.deployment)
	var record: Dictionary=slots.get(str(slot if slot>=0 else int(target.deployment.get("slot",-1))),{})
	if not record.is_empty():
		record.instance_ids=copy.instance_ids.values()
		target.deployment=summarize_slots(slots)
	var kit := str(board.get("authority_kit_id",record.get("kit","")))
	if target.profile.kits.has(kit):
		var saved := copy.duplicate(true)
		if not creative:saved.component_runtime={} # Registry is the single saved copy of owned mutable bytes.
		target.profile.kits[kit].board=saved
	if not Profile.valid(target.profile):return "Invalid component persistence snapshot"
	if Profile.same(target.profile,account(peer).profile) and target.deployment==account(peer).deployment:return ""
	target.revision+=1
	if not persist(next):return "Host component save failed"
	board.instance_ids=copy.instance_ids;board.component_runtime=copy.component_runtime
	return ""
