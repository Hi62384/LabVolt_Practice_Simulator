extends SceneTree
const Claims=preload("res://scripts/campus/lost_found/claim_authority.gd")
const Ledger=preload("res://scripts/inventory_authority/ledger.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var owner:=Node.new();root.add_child(owner)
	var token: String=Crypto.new().generate_random_bytes(16).hex_encode()
	var before: Dictionary=await Claims.status(owner,token)
	var first: Dictionary=await Claims.claim(owner,token)
	var after: Dictionary=await Claims.status(owner,token)
	var second: Dictionary=await Claims.claim(owner,token)
	assert(first.get("ok",false))
	assert(before.get("ok",false) and not before.get("claimed",true))
	assert(after.get("ok",false) and after.get("claimed",false))
	assert(not second.get("ok",false) and second.get("claimed",false))
	var pending_token: String=Crypto.new().generate_random_bytes(16).hex_encode()
	var holder: String=Crypto.new().generate_random_bytes(16).hex_encode()
	assert((await Claims.reserve(owner,pending_token,holder)).get("ok",false))
	assert((await Claims.status(owner,pending_token)).get("reserved",false))
	assert((await Claims.release(owner,pending_token,holder)).get("ok",false))
	assert(not (await Claims.status(owner,pending_token)).get("claimed",true))
	assert((await Claims.reserve(owner,pending_token,holder)).get("ok",false))
	assert((await Claims.prepare(owner,pending_token,holder)).get("ok",false))
	assert((await Claims.commit(owner,pending_token,holder)).get("ok",false))
	assert((await Claims.commit(owner,pending_token,holder)).get("ok",false))
	assert((await Claims.status(owner,pending_token)).get("claimed",false))
	assert(not (await Claims.claim(owner,"bad")).get("ok",false))
	await recover_host_claims()
	print("CLAIM_HTTP_PASS")
	quit(0)

func recover_host_claims() -> void:
	var game: Node=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for frame in 4:await process_frame
	var world: Node=game.discarded_items
	world.set_process(false)
	var authority: Node=game.electronics_trade.authority
	authority.set_process(false)
	var path:="user://lost-found-restart-fixture"
	var ledger:=Ledger.new()
	assert(ledger.open(path)==OK)
	var profile: Dictionary=game.electronics.profile.data.duplicate(true)
	profile.dorm.carry_items=[]
	profile.dorm.carried_components=[]
	var identity: String=profile.dorm.owner
	assert(ledger.bind(1,identity,Crypto.new().generate_random_bytes(32).hex_encode(),profile).ok)
	authority.ledger=ledger
	game.session.online=true
	var holder:=Crypto.new().generate_random_bytes(16).hex_encode()
	var competitor:=Crypto.new().generate_random_bytes(16).hex_encode()
	var delivered:=Crypto.new().generate_random_bytes(16).hex_encode()
	var interrupted:=Crypto.new().generate_random_bytes(16).hex_encode()
	for token in [delivered,interrupted]:
		assert((await Claims.reserve(world,token,holder)).ok)
		assert(ledger.begin_lost_found_receipt(token,holder))
		assert((await Claims.prepare(world,token,holder)).ok)
	var initial: int=ledger.account(1).profile.inventory.get("r1000",0)
	var parcel := {"item":{"kind":"component","type":"r1000","instance":""},"stock":{"r1000":1},"carried_stock":{"r1000":1},
		"kits":{},"tiers":{},"bags":{},"instances":{},"supplies":{},"definitions":{},"carried_instances":[]}
	assert(world._deliver_drop(1,6,{"parcel":parcel},delivered,holder))
	assert(ledger.account(1).profile.inventory.r1000==initial+1)
	assert((await Claims.reserve(world,delivered,competitor)).reserved)
	assert((await Claims.reserve(world,interrupted,competitor)).reserved)
	var reopened:=Ledger.new()
	assert(reopened.open(path)==OK)
	authority.ledger=reopened
	game.session.online=true
	await world._recover_claim_receipt()
	await world._recover_claim_receipt()
	assert(reopened.state.lost_found_claims.is_empty())
	assert(reopened.state.accounts[identity].profile.inventory.r1000==initial+1)
	assert((await Claims.status(world,delivered)).claimed)
	assert((await Claims.reserve(world,interrupted,competitor)).ok)
	game.session.online=false
	game.queue_free()
	await process_frame
	print("LOST_FOUND_HOST_RESTART_PASS")
