extends Node
var game: Node
var trades := {}
var current := {}
var journal := {}
var host_identity := ""
var clock := 0.0
var authority: Node
func build(owner_game: Node) -> void:
	game=owner_game
	var cfg := ConfigFile.new()
	if cfg.load("user://trade_journal.cfg")!=OK:cfg.load("user://trade_journal.cfg.bak")
	var loaded_journal=cfg.get_value("transactions","committed",{})
	journal=loaded_journal if loaded_journal is Dictionary else {}
	host_identity=cfg.get_value("transactions","host","")
	if host_identity=="":host_identity=Crypto.new().generate_random_bytes(16).hex_encode();save_journal()
	game.session.roster_changed.connect(clean_disconnected)
	game.session.restarted.connect(func():current={};trades.clear())
	authority=preload("res://scripts/inventory_authority/network.gd").new();authority.name="InventoryAuthority";add_child(authority);authority.build(game,host_identity)
func profile():return game.electronics.profile
func request(action: Dictionary) -> void:
	if action.get("op")=="confirm" and not action.has("revision"):
		action=action.duplicate(true);action.revision=current.get("revision",0)
	if multiplayer.is_server():accept(1,action)
	else:command.rpc_id(1,action)
@rpc("any_peer","call_remote","reliable",5)
func command(action: Dictionary) -> void:
	if multiplayer.is_server():accept(multiplayer.get_remote_sender_id(),action)
func accept(peer: int,action: Dictionary) -> void:
	if not game.session.online or game.school.mode=="Creative Freeplay" or not game.session.roster.has(peer) or var_to_bytes(action).size()>1048576:return
	var op := str(action.get("op",""))
	if op=="invite":
		if not preload("res://scripts/electronics_profile.gd").quantity(action.get("target"),2147483647):return
		var target := int(action.target)
		if target==peer or not game.session.roster.has(target) or authority.ledger.account(peer).is_empty() or authority.ledger.account(target).is_empty():return
		for trade in trades.values():
			if peer in trade.peers or target in trade.peers:return
		var id := Crypto.new().generate_random_bytes(16).hex_encode()
		trades[id]={"id":id,"peers":[peer,target],"offers":{peer:{},target:{}},"definitions":{},"instances":{peer:{},target:{}},"confirmed":[],"prepared":[],"phase":"review","revision":0};publish(trades[id]);return
	var id := str(action.get("id",""))
	if not trades.has(id) or peer not in trades[id].peers:return
	var trade: Dictionary=trades[id]
	if op=="cancel" and trade.phase!="committed":cancel(trade);return
	if trade.phase!="review":return
	if op=="offer":
		var offer=action.get("items",{});var definitions=action.get("definitions",{})
		if not offer is Dictionary or offer.size()>64 or not definitions is Dictionary:return
		if authority.ledger.offer_error(peer,offer,definitions)!="":return
		var catalog: Dictionary=preload("res://scripts/custom_circuit.gd").catalog(definitions)
		for type in offer:
			if not catalog.has(type) or not (offer[type] is int or offer[type] is float) or not is_finite(float(offer[type])) or int(offer[type])<0 or int(offer[type])>100000 or float(offer[type])!=floor(float(offer[type])):return
			if str(type).begins_with("ic:") and preload("res://scripts/custom_circuit.gd").validate(type,definitions)!="":return
		for type in definitions:
			if trade.definitions.has(type) and not preload("res://scripts/electronics_profile.gd").same(trade.definitions[type],definitions[type]):return
		trade.definitions.merge(definitions);trade.offers[peer]=offer.duplicate(true);trade.confirmed.clear();trade.revision+=1
		trade.instances[peer]={}
		var selected: Dictionary=preload("res://scripts/inventory_authority/component_persistence.gd").selected(authority.ledger.account(peer).profile,offer,authority.ledger.account(peer).deployment.get("instance_ids",[]))
		for instance in selected:trade.instances[peer][instance]=authority.ledger.instance_hash(selected[instance])
	elif op=="confirm":
		if action.get("revision",-1)!=trade.revision:publish(trade);return
		if peer not in trade.confirmed:trade.confirmed.append(peer)
		if trade.confirmed.size()==2:
			# Confirmation is of the final offers. Client prepare acknowledgements never prove stock.
			var receipt: Dictionary=authority.ledger.exchange(id,trade.peers,trade.offers,trade.definitions,trade.instances)
			if not receipt.get("ok",false):cancel(trade);return
			var deliveries := {}
			for token in receipt.deliveries:deliveries[token]=false
			journal[id]={"deliveries":deliveries,"authoritative":true}
			save_journal() # Ledger contains the durable decision even if this delivery hint fails.
			trade.phase="committed";publish(trade);deliver()
	if trades.has(id) and trade.phase=="review":publish(trade)
func publish(trade: Dictionary) -> void:
	for peer in trade.peers:
		if peer==1:receive(trade)
		elif game.session.roster.has(peer):receive.rpc_id(peer,trade)
@rpc("authority","call_remote","reliable",5)
func receive(trade: Dictionary) -> void:
	current=trade.duplicate(true)
	if game.electronics.active and game.electronics.current_page=="trade":game.electronics.open("trade")
@rpc("authority","call_remote","reliable",5)
func prepare(payload: Dictionary) -> void:
	var error: String=profile().prepare_trade(payload)
	if multiplayer.is_server():prepared(1,payload.id,error)
	else:prepared_reply.rpc_id(1,payload.id,error)
@rpc("any_peer","call_remote","reliable",5)
func prepared_reply(id: String,error: String) -> void:
	if multiplayer.is_server():prepared(multiplayer.get_remote_sender_id(),id,error)
func prepared(peer: int,id: String,error: String) -> void:
	if not trades.has(id):return
	var trade: Dictionary=trades[id]
	if trade.phase!="preparing" or peer not in trade.peers:return
	if error!="":cancel(trade);return
	if peer not in trade.prepared:trade.prepared.append(peer)
	if trade.prepared.size()!=2:return
	var deliveries := {}
	for participant in trade.peers:
		var token := str(game.school.identities.get(participant,""))
		if token=="":cancel(trade);return
		deliveries[token]=false
	journal[id]={"deliveries":deliveries}
	if not save_journal():journal.erase(id);cancel(trade);return
	trade.phase="committed";publish(trade);deliver()
func save_journal() -> bool:
	var cfg := ConfigFile.new();cfg.set_value("transactions","committed",journal);cfg.set_value("transactions","host",host_identity)
	if cfg.save("user://trade_journal.cfg.tmp")!=OK:return false
	if FileAccess.file_exists("user://trade_journal.cfg") and DirAccess.copy_absolute("user://trade_journal.cfg","user://trade_journal.cfg.bak")!=OK:return false
	return DirAccess.rename_absolute("user://trade_journal.cfg.tmp","user://trade_journal.cfg")==OK
func deliver() -> void:
	# Reconstruct missing delivery hints after a crash between atomic commit and journal write.
	if is_instance_valid(authority):
		if not authority.ledger.receipt_delivery_hints(journal):return
	for id in journal:
		if not journal[id] is Dictionary or not journal[id].get("deliveries") is Dictionary:continue
		if journal[id].get("authoritative",false) and not journal[id].get("_archive_seen",false):continue
		for peer in game.school.identities:
			var token: String=game.school.identities[peer]
			if journal[id].deliveries.has(token) and not journal[id].deliveries[token]:
				if journal[id].get("authoritative",false):
					if authority.ledger.bindings.get(peer,"")!=token:continue
					var result: Dictionary=authority.ledger.snapshot(peer)
					if peer==1:authoritative_commit(id,result)
					elif game.session.roster.has(peer):authoritative_commit.rpc_id(peer,id,result)
				elif peer==1:commit(id)
				elif game.session.roster.has(peer):commit.rpc_id(peer,id)
@rpc("authority","call_remote","reliable",5)
func commit(id: String) -> void:
	var callback: Callable=profile().authority_submit;profile().authority_submit=Callable()
	var error: String=profile().commit_trade(id)
	profile().authority_submit=callback
	if error!="":game.ui.log_message(error);return
	if current.get("id")==id:current={}
	if game.electronics.active and game.electronics.current_page=="trade":game.electronics.open("trade")
	game.ui.log_message("Trade complete. Components and required blueprints saved.")
	if multiplayer.is_server():acknowledge(1,id)
	else:ack.rpc_id(1,id)
@rpc("any_peer","call_remote","reliable",5)
func ack(id: String) -> void:
	if multiplayer.is_server():acknowledge(multiplayer.get_remote_sender_id(),id)
func acknowledge(peer: int,id: String) -> void:
	var token := str(game.school.identities.get(peer,""))
	if is_instance_valid(authority) and not authority.ledger.receipt_delivery_hints(journal):return
	if not journal.has(id) or not journal[id] is Dictionary or not journal[id].get("deliveries") is Dictionary or not journal[id].deliveries.has(token):return
	if journal[id].get("authoritative",false) and not journal[id].get("_archive_seen",false):return
	if journal[id].get("authoritative",false) and authority.ledger.bindings.get(peer,"")!=token:return
	journal[id].deliveries[token]=true;save_journal()
	if journal[id].deliveries.values().all(func(done):return done):trades.erase(id)
func cancel(trade: Dictionary) -> void:
	for peer in trade.peers:
		if peer==1:abort(trade.id)
		elif game.session.roster.has(peer):abort.rpc_id(peer,trade.id)
	trades.erase(trade.id)
@rpc("authority","call_remote","reliable",5)
func abort(id: String) -> void:
	profile().abort_trade(id)
	if current.get("id")==id:current={}
	if game.electronics.active and game.electronics.current_page=="trade":game.electronics.open("trade")
	game.ui.log_message("Trade cancelled. No components exchanged.")
func clean_disconnected() -> void:
	if not multiplayer.is_server():return
	for id in trades.keys():
		var trade: Dictionary=trades[id]
		if trade.phase!="committed" and trade.peers.any(func(peer):return not game.session.roster.has(peer)):cancel(trade)
func _process(delta: float) -> void:
	clock+=delta
	if clock<2 or not is_instance_valid(game):return
	clock=0
	if multiplayer.is_server() and game.session.online:deliver()
	var pending: String=profile().data.get("pending_trade",{}).get("id","")
	if pending!="" and game.session.online:
		if multiplayer.is_server():recover(1,pending,str(profile().data.pending_trade.get("host","")))
		else:recover_request.rpc_id(1,pending,str(profile().data.pending_trade.get("host","")))
func menu(parent: Node) -> void:
	preload("res://scripts/ui/personal_inventory/panels.gd").trade_menu(self,parent)
@rpc("any_peer","call_remote","reliable",5)
func recover_request(id: String,origin: String) -> void:
	if multiplayer.is_server():recover(multiplayer.get_remote_sender_id(),id,origin)
func recover(peer: int,id: String,origin: String) -> void:
	if origin!=host_identity:return
	if is_instance_valid(authority) and not authority.ledger.receipt_delivery_hints(journal):return
	if journal.has(id):deliver()
	elif not trades.has(id):
		if peer==1:abort(id)
		else:abort.rpc_id(peer,id)
@rpc("authority","call_remote","reliable",5)
func authoritative_commit(id: String,snapshot: Dictionary) -> void:
	if profile().accept_authority(snapshot)!=OK:return
	if current.get("id")==id:current={}
	if game.electronics.active and game.electronics.current_page=="trade":game.electronics.open("trade")
	game.ui.log_message("Trade complete. Components, dependencies and firmware saved.")
	if multiplayer.is_server():acknowledge(1,id)
	else:ack.rpc_id(1,id)
func offer_definitions(items: Dictionary) -> Dictionary:
	var result := {};var owned: Dictionary=profile().data.get("blueprints",{})
	for type in items:
		if str(type).begins_with("ic:") and int(items[type])>0 and owned.has(type):
			authority.ledger.dependencies(str(type),owned,result)
	return result
