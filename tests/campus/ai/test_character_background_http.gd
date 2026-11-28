extends SceneTree
## Native HTTPRequest sockets against the authored loopback provider. These are
## scheduling/protocol measurements, not claims about live model performance.
const Client = preload("res://scripts/campus/ai/host_openai_client.gd")
const TEST_KEY := "sk-test-12345678901234567890"
const REPLACEMENT_KEY := "sk-replacement-12345678901234567890"
const INSTRUCTIONS := "HTTP_FIXTURE_GENERATE_DOSSIER Return the authored transport fixture."
var failures: Array[String] = []
var checks := 0
var fixture := ""
var evidence := {"source": "actual loopback HTTP; authored delays and token usage, not live AI"}

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func _start_background(client: Node, result_box: Dictionary, context: Dictionary, output_limit := 10000) -> void:
	result_box.started = Time.get_ticks_msec()
	result_box.done = false
	result_box.result = await client.generate_character_dossier(INSTRUCTIONS, context, output_limit)
	result_box.finished = Time.get_ticks_msec()
	result_box.done = true

func _wait_done(box: Dictionary, label: String) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while not box.get("done", false) and Time.get_ticks_msec() < deadline:
		await create_timer(0.015).timeout
	_check(box.get("done", false), label + " resolves its waiting coroutine")
	return box.get("done", false)

func _request_log() -> Array:
	var request := HTTPRequest.new()
	root.add_child(request)
	request.timeout = 5.
	request.body_size_limit = 8 * 1024 * 1024
	var started := request.request(fixture + "/fixture/requests", PackedStringArray(["Authorization: Bearer " + TEST_KEY]))
	if started != OK:
		_check(false, "Fixture inspection starts")
		request.queue_free()
		return []
	var completed: Array = await request.request_completed
	request.queue_free()
	if int(completed[0]) != HTTPRequest.RESULT_SUCCESS or int(completed[1]) != 200:
		_check(false, "Fixture inspection succeeds")
		return []
	var parser := JSON.new()
	if parser.parse(completed[3].get_string_from_utf8()) != OK:
		_check(false, "Fixture log is valid JSON")
		return []
	return parser.data.get("requests", [])

func _matching(log: Array, marker: String) -> Array:
	return log.filter(func(row): return row.path == "/v1/responses" and marker in str(row.body.get("input", "")))

func _wait_received(marker: String) -> bool:
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		if not _matching(await _request_log(), marker).is_empty():
			return true
		await create_timer(0.02).timeout
	_check(false, "Background request crosses actual HTTP boundary: " + marker)
	return false

func _generation_totals(client: Node) -> Dictionary:
	var totals := {"requests": 0, "success": 0, "input": 0, "output": 0, "cached": 0, "reasoning": 0}
	for row in client.usage_tracker.rows.values():
		if row.get("purpose", "") != "character_generation":
			continue
		_check(row.get("type", "") == "feature", "Population usage is a production feature, not a setup test")
		for key in totals:
			totals[key] += int(row.get(key, 0))
	return totals

func _run() -> void:
	create_timer(45.).timeout.connect(func(): push_error("Background HTTP test timed out"); quit(1))
	var port := OS.get_environment("LABVOLT_OPENAI_FIXTURE_PORT")
	fixture = "http://127.0.0.1:%s/v1" % ("28768" if port.is_empty() else port)
	var client := Client.new()
	root.add_child(client)
	_check(client.set_local_test_endpoint(fixture) and client.set_session_key(TEST_KEY), "Loopback client is configured")
	_check(client.configure("gpt-5.4-mini", 64, "low", true) == OK, "Production client settings are accepted")
	_check((await client.verify_class_connection()).get("ok", false), "Foreground connection is verified over HTTP")
	var first := {}
	_start_background(client, first, {"marker": "BG_PARALLEL", "delay_ms": 1200}, 16)
	await _wait_received("BG_PARALLEL")
	_check(client.background_busy and not client.busy and not first.done, "Background reservation holds only its independent lane")
	var duplicate: Dictionary = await client.generate_character_dossier(INSTRUCTIONS, {"marker": "BG_DUPLICATE"})
	_check(not duplicate.get("ok", true) and not duplicate.has("measurement"), "Duplicate population job is rejected before HTTP or usage accounting")
	var foreground_started := Time.get_ticks_msec()
	var foreground: Dictionary = await client.respond("test prompt")
	evidence.foreground_during_background_ms = Time.get_ticks_msec() - foreground_started
	_check(foreground.get("ok", false) and foreground.get("text", "") == "fixture answer", "Foreground dialogue completes through actual HTTP while generation is pending")
	_check(not first.done and client.background_busy and not client.busy, "Foreground completion leaves the active population request untouched")
	_check(foreground.get("measurement", {}).get("usage", {}) == {"input": 10, "output": 20, "reasoning": 8}, "Foreground reports the exact fixture provider usage")
	await _wait_done(first, "Successful generation")
	_check(first.result.get("ok", false) and JSON.parse_string(first.result.get("text", "{}")) == {"fixture_dossier": "BG_PARALLEL"}, "Completed background result reaches its original caller")
	_check(first.result.get("measurement", {}).get("usage", {}) == {"input": 611, "output": 231, "cached": 128, "reasoning": 17}, "Background records actual HTTP usage including cached input")
	_check(int(first.result.get("measurement", {}).get("latency_ms", 0)) >= 1000, "Background latency includes the provider's measured delay")
	evidence.background_http_ms = first.result.get("measurement", {}).get("latency_ms", null)
	var log := await _request_log()
	var first_wires := _matching(log, "BG_PARALLEL")
	_check(first_wires.size() == 1 and _matching(log, "BG_DUPLICATE").is_empty(), "Exactly one population request crosses the wire despite a duplicate attempt")
	if first_wires.size() == 1:
		_check(int(first_wires[0].body.max_output_tokens) == 4096 and first_wires[0].body.store == false, "Background request uses its bounded dossier budget and disables provider storage")

	var cancelled := {}
	_start_background(client, cancelled, {"marker": "BG_CANCEL", "delay_ms": 1100})
	await _wait_received("BG_CANCEL")
	var previous_epoch: int = client._background_epoch
	client.cancel_background_generation()
	await _wait_done(cancelled, "Explicit cancellation")
	_check(client._background_epoch == previous_epoch + 1 and not client.background_busy, "Cancellation advances the epoch and frees the background reservation")
	_check(cancelled.result.get("cancelled", false) and not cancelled.result.get("ok", true) and not cancelled.result.has("text"), "Cancelled output is never publishable as a dossier")
	_check(cancelled.result.get("measurement", {}).get("usage", {}).is_empty(), "Cancelled response without usage keeps token counts unknown")
	var replacement := {}
	_start_background(client, replacement, {"marker": "BG_REPLACEMENT", "delay_ms": 2400}, 50000)
	await _wait_received("BG_REPLACEMENT")
	await create_timer(1.25).timeout
	_check(client.background_busy and not replacement.done and cancelled.result.get("cancelled", false), "Late completion from a cancelled HTTP request cannot clear or overwrite its replacement epoch")
	var during_replacement: Dictionary = await client.respond("test prompt")
	_check(during_replacement.get("ok", false) and client.background_busy, "Foreground remains available during a replacement background request")
	await _wait_done(replacement, "Replacement generation")
	_check(replacement.result.get("ok", false) and JSON.parse_string(replacement.result.get("text", "{}")) == {"fixture_dossier": "BG_REPLACEMENT"}, "Replacement receives only its own completed result")
	log = await _request_log()
	var replacement_wires := _matching(log, "BG_REPLACEMENT")
	_check(replacement_wires.size() == 1 and int(replacement_wires[0].body.max_output_tokens) == 16000, "Replacement generation obeys the maximum output budget")
	_check(_generation_totals(client) == {"requests": 3, "success": 2, "input": 1222, "output": 462, "cached": 256, "reasoning": 34}, "One cancellation is counted once without inventing usage or duplicating successful jobs")

	var changed := {}
	_start_background(client, changed, {"marker": "BG_CONFIG_CHANGE", "delay_ms": 1800})
	await _wait_received("BG_CONFIG_CHANGE")
	_check(client.configure("gpt-4.1", 64, "", true) == OK, "Selecting a new model cancels the old generation lane")
	await _wait_done(changed, "Model change cancellation")
	_check(changed.result.get("cancelled", false) and not client.background_busy, "Model change cannot leave a population caller stranded")
	_check((await client.verify_class_connection()).get("ok", false) and client.verified_for_class(), "Newly selected connection can be verified immediately")
	var auth_failure := {}
	_start_background(client, auth_failure, {"marker": "BG_AUTH_CURRENT", "delay_ms": 100, "reject_credentials": true})
	await _wait_done(auth_failure, "Current credential rejection")
	_check(not auth_failure.result.get("ok", true) and not client.verified_for_class() and not client.verification_error.is_empty(), "A current background authentication failure invalidates current connection verification")
	_check((await client.verify_class_connection()).get("ok", false), "Connection can be reverified after the authored rejection")
	var old_auth := {}
	_start_background(client, old_auth, {"marker": "BG_AUTH_OLD", "delay_ms": 1000, "reject_credentials": true})
	await _wait_received("BG_AUTH_OLD")
	_check(client.set_session_key(REPLACEMENT_KEY), "Host can replace the session credential while the old job is pending")
	_check((await client.verify_class_connection()).get("ok", false) and client.verified_for_class(), "Replacement credential is independently verified through foreground HTTP")
	await _wait_done(old_auth, "Old credential rejection")
	_check(not old_auth.result.get("ok", true) and client.verified_for_class() and client.verification_error.is_empty(), "An old credential's delayed rejection cannot invalidate the newly verified connection")

	var disconnected := {}
	_start_background(client, disconnected, {"marker": "BG_DISCONNECT", "delay_ms": 1000})
	await _wait_received("BG_DISCONNECT")
	client.disconnect_key()
	await _wait_done(disconnected, "Disconnect cancellation")
	_check(disconnected.result.get("cancelled", false) and not client.background_busy and not client.configured(), "Disconnect resolves generation and removes its active credential")
	var totals := _generation_totals(client)
	_check(totals == {"requests": 7, "success": 2, "input": 1222, "output": 462, "cached": 256, "reasoning": 34}, "All seven actual population requests, including cancellation and auth errors, are counted exactly once")
	var reloaded := Client.new()
	root.add_child(reloaded)
	_check(_generation_totals(reloaded) == totals, "Measured population usage survives loading persisted settings")
	_check(not FileAccess.get_file_as_string(Client.SETTINGS_PATH).contains("sk-"), "Neither fixture credential is written to persisted usage/settings")
	evidence.background_totals = totals
	evidence.checks = checks
	evidence.failures = failures
	print("CHARACTER_BACKGROUND_HTTP_EVIDENCE ", JSON.stringify(evidence))
	print("CHARACTER_BACKGROUND_HTTP ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " (loopback fixture, not live AI)")
	client.queue_free()
	reloaded.queue_free()
	quit(0 if failures.is_empty() else 1)
