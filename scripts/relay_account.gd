extends Node

const PROFILE := "user://relay-account.cfg"
const LOGIN_CANCEL := "user://relay-account/cancel-login"
const BUNDLE := "res://relay/relay-tools-4.158.0.zip"
const DAILY_REQUESTS := 100000
var identity := {}
var busy := false

func cancel_login() -> Error:
	var marker := FileAccess.open(LOGIN_CANCEL, FileAccess.WRITE)
	if marker == null:
		return FileAccess.get_open_error()
	marker.close()
	return OK

func _ready() -> void:
	var profile := ConfigFile.new()
	if profile.load(PROFILE) == OK:
		identity = profile.get_value("relay", "identity", {})

func connected() -> bool:
	return not str(identity.get("host", "")).is_empty() and not str(identity.get("host_key", "")).is_empty()

func endpoint() -> String:
	return "wss://" + str(identity.host) if connected() else ""

func set_identity(value: Dictionary) -> Error:
	var profile := ConfigFile.new()
	profile.load(PROFILE)
	profile.set_value("relay", "identity", value)
	var error := profile.save(PROFILE)
	if error == OK:
		identity = value
	return error

func run(action: String, account_id := "") -> Dictionary:
	if busy:
		return {"ok": false, "error": "Cloudflare setup is already running."}
	busy = true
	var result := await _run(action, account_id)
	busy = false
	return result

func _run(action: String, account_id: String) -> Dictionary:
	var directory := ProjectSettings.globalize_path("user://relay-account")
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return {"ok": false, "error": "Could not create the Cloudflare setup folder."}
	if action == "login" and FileAccess.file_exists(LOGIN_CANCEL):
		if DirAccess.remove_absolute(LOGIN_CANCEL) != OK:
			return {"ok": false, "error": "Could not reset the Cloudflare sign in."}
	var tools := OS.get_environment("LABVOLT_RELAY_TOOLS")
	if tools.is_empty():
		tools = directory.path_join("tools-4.158.0")
		if not FileAccess.file_exists(tools.path_join("installed")):
			var installer := Thread.new()
			error = installer.start(_install_tools.bind(tools))
			if error == OK:
				while installer.is_alive():
					await get_tree().process_frame
				error = installer.wait_to_finish()
			if error != OK:
				return {"ok": false, "error": "Could not prepare the Cloudflare setup tools. " + error_string(error)}
	var helper := FileAccess.open(tools.path_join("account.mjs"), FileAccess.WRITE)
	var source := FileAccess.get_file_as_bytes("res://relay/account.mjs")
	if helper == null or source.is_empty() or not helper.store_buffer(source):
		return {"ok": false, "error": "Could not update the Cloudflare account helper."}
	helper.close()
	var result_path := directory.path_join("result.json")
	if FileAccess.file_exists(result_path) and DirAccess.remove_absolute(result_path) != OK:
		return {"ok": false, "error": "Could not reset Cloudflare setup."}
	var process_id := OS.create_process(tools.path_join("node.exe"), [tools.path_join("account.mjs"), action, directory, account_id])
	if process_id < 1:
		return {"ok": false, "error": "Could not start Cloudflare setup."}
	while OS.is_process_running(process_id):
		await get_tree().create_timer(0.25).timeout
	var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(result_path)) if FileAccess.file_exists(result_path) else null
	if FileAccess.file_exists(result_path):
		DirAccess.remove_absolute(result_path)
	return result if result is Dictionary else {"ok": false, "error": "Cloudflare setup exited unexpectedly."}

static func _install_tools(directory: String) -> Error:
	var marker := directory.path_join("installed")
	if FileAccess.file_exists(marker):
		return OK
	var zip := ZIPReader.new()
	var error := zip.open(BUNDLE)
	if error != OK:
		return error
	for path in zip.get_files():
		if path.ends_with("/"):
			continue
		var output := directory.path_join(path)
		error = DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		if error != OK:
			return error
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null:
			return FileAccess.get_open_error()
		if not file.store_buffer(zip.read_file(path)):
			return file.get_error()
	var complete := FileAccess.open(marker, FileAccess.WRITE)
	return OK if complete != null else FileAccess.get_open_error()

static func invite(host: String, code: String) -> String:
	return code + "@" + host.trim_prefix("labvolt-relay.").trim_suffix(".workers.dev")

static func parse_invite(value: String, fallback: String) -> Dictionary:
	var parts := value.strip_edges().split("@")
	if parts.is_empty():
		return {}
	var code := parts[0].to_upper().replace("-", "").replace(" ", "")
	if code.length() != 10 or parts.size() > 2:
		return {}
	for character in code:
		if not character in "23456789ABCDEFGHJKLMNPQRSTUVWXYZ":
			return {}
	if parts.size() == 1:
		return {"code": code, "endpoint": fallback} if not fallback.is_empty() else {}
	var slug := parts[1].to_lower()
	var pattern := RegEx.create_from_string("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")
	if pattern.search(slug) == null:
		return {}
	return {"code": code, "endpoint": "wss://labvolt-relay.%s.workers.dev" % slug}

static func dashboard(account_id: String) -> String:
	return "https://dash.cloudflare.com/" + account_id + "/workers-and-pages"

func record_usage(connections: int, messages: int) -> void:
	if connections == 0 and messages == 0:
		return
	var meter := _load_meter()
	var counts: Vector2i = meter.get_value(_meter_key(), "counts", Vector2i.ZERO)
	meter.set_value(_meter_key(), "counts", counts + Vector2i(connections, messages))
	meter.save("user://relay-usage.cfg")

func estimated_remaining() -> int:
	var counts: Vector2i = _load_meter().get_value(_meter_key(), "counts", Vector2i.ZERO)
	return maxi(0, DAILY_REQUESTS - counts.x - ceili(counts.y / 20.0))

func _meter_key() -> String:
	return str(identity.get("account_id", ""))

func _load_meter() -> ConfigFile:
	var meter := ConfigFile.new()
	meter.load("user://relay-usage.cfg")
	var today := Time.get_date_string_from_system(true)
	if meter.get_value("meter", "utc_date", "") != today:
		meter.clear()
		meter.set_value("meter", "utc_date", today)
	return meter
