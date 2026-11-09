extends SceneTree
## Two real ENet peers exercise the production inventory appearance RPC.
const Network = preload("res://scripts/inventory_authority/network.gd")
const Coordinator = preload("res://scripts/avatar_cosmetics/core/coordinator.gd")
const Core = preload("res://scripts/avatar_cosmetics/core/avatar_core.gd")
const Profile = preload("res://scripts/electronics_profile.gd")
var role := "host"
var port := 26147
var failures := 0
var network: Node
var game: FixtureGame
var peer: ENetMultiplayerPeer

class FixtureSession extends Node:
	var roster := {1:true,2:true}
	func connected_peers() -> Array: return [2]

class FixtureGame extends Node:
	var session: FixtureSession
	var cosmetic_appearances := {}
	var avatars := {}
	func _ready() -> void:
		session = FixtureSession.new(); add_child(session)
	func _set_avatar_model(_id: int, _model: Variant) -> void: pass

func expect(value: bool, label: String) -> void:
	if not value: failures += 1; printerr("FAIL ", role, ": ", label)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: role = args[0]
	if args.size() > 1: port = int(args[1])
	game = FixtureGame.new(); game.name = "Game"; root.add_child(game)
	network = Network.new(); network.name = "InventoryAuthority"; game.add_child(network)
	network.game = game
	peer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(port, 2) if role == "host" else peer.create_client("127.0.0.1", port)
	expect(error == OK, "ENet transport opened")
	if error != OK: quit(1); return
	root.multiplayer.multiplayer_peer = peer
	var cosmetics := Coordinator.new()
	expect(cosmetics.load_catalog(), "production catalog loads")
	if role == "host":
		for i in 100:
			if peer.get_peer(2) != null: break
			await create_timer(.05).timeout
		expect(peer.get_peer(2) != null, "client connected")
		var catalog: Dictionary = cosmetics.catalog
		var shoe: Dictionary = catalog["shoes.velocity_runner"]
		var synthetic := Profile.new(); synthetic.open("avatar-transport-synthetic")
		var profile: Dictionary = synthetic.data.duplicate(true)
		profile.dollars = 37
		profile.owned_cosmetics = [shoe.id]
		profile.avatar_cosmetics = {"version":1,"body":{"height":1.25,"width":.8},"equipped":{"footwear":{"id":shoe.id,"parameters":{}}}}
		var identity := "a".repeat(48)
		expect(network.ledger.open("user://avatar-transport-ledger") == OK, "isolated production ledger opened")
		var binding: Dictionary = network.ledger.bind(2, identity, "b".repeat(64), profile)
		expect(binding.get("ok",false) and network.ledger.bindings.get(2,"") == identity, "production credential binding established")
		network._publish_cosmetic_appearances()
		await create_timer(.5).timeout
		# The sender refuses an unowned item before it enters a packet.
		var unowned: Dictionary = network.ledger.state.accounts[identity].profile
		unowned.avatar_cosmetics.equipped.footwear.id = "shoes.ionstep"
		network._publish_cosmetic_appearances()
		await create_timer(.5).timeout
		unowned.avatar_cosmetics.equipped.footwear.id = shoe.id
		network._publish_cosmetic_appearances()
		await create_timer(.5).timeout
	else:
		for i in 100:
			if game.cosmetic_appearances.has(2): break
			await create_timer(.05).timeout
		expect(game.cosmetic_appearances.has(2), "received production authority RPC")
		if game.cosmetic_appearances.has(2):
			var appearance: Dictionary = game.cosmetic_appearances[2]
			expect(appearance.body.height == 1.25 and appearance.body.width == .8 and appearance.equipped.footwear.id == "shoes.velocity_runner", "remote body and equipped ID match host")
			expect(not appearance.has("dollars") and var_to_bytes(appearance).size() < 65536, "only compact appearance replicated")
		await create_timer(1.2).timeout
		var after: Dictionary = game.cosmetic_appearances.get(2,{})
		expect(after.get("equipped",{}).get("footwear",{}).get("id","") == "shoes.velocity_runner", "valid republish restores authorized appearance")
	print("AVATAR_TRANSPORT ", role, " failures=", failures)
	root.multiplayer.multiplayer_peer = null
	peer.close()
	quit(1 if failures else 0)
