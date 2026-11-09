extends SceneTree

const Ledger = preload("res://scripts/inventory_authority/ledger.gd")
const Profile = preload("res://scripts/electronics_profile.gd")

func _initialize() -> void:
	var profile = Profile.new()
	profile.open("local-inventory-test")
	profile.data.erase("dorm")
	var identity := "a".repeat(48)
	var secret := "1".repeat(64)
	var ledger = Ledger.new()
	if ledger.open("user://local-inventory-ledger") != OK:
		fail("Could not open ledger")
		return
	var first: Dictionary = ledger.bind(1, identity, secret, profile.data)
	if not first.get("ok", false):
		fail("Initial enrollment failed")
		return
	ledger.unbind(1)
	var local: Dictionary = profile.data.duplicate(true)
	local.inventory.r1000 = 25
	local.notebook = "Local progress"
	var rejoined: Dictionary = ledger.bind(2, identity, secret, local)
	if not rejoined.get("ok", false) or rejoined.profile.inventory.r1000 != 25 or rejoined.profile.notebook != "Local progress":
		fail("Local profile was not used on rejoin")
		return
	var stale: Dictionary = profile.data.duplicate(true)
	var repeated: Dictionary = ledger.bind(2, identity, secret, stale)
	if not repeated.get("ok", false) or repeated.profile.inventory.r1000 != 25:
		fail("Repeated enrollment replaced the active inventory")
		return
	var purchased: Dictionary = ledger.transact(2, "purchase", "buy", ["r1000", 1])
	if not purchased.get("ok", false) or purchased.profile.inventory.r1000 != 26:
		fail("Session inventory operation failed")
		return
	print("LOCAL_INVENTORY PASS")
	quit()

func fail(message: String) -> void:
	push_error(message)
	quit(1)
