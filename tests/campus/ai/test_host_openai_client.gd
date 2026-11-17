extends SceneTree

const Client=preload("res://scripts/campus/ai/host_openai_client.gd")
var failures: Array[String]=[]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var client: Node=Client.new()
	root.add_child(client)
	if not client.set_local_test_endpoint("http://127.0.0.1:28768/v1"):failures.append("Test endpoint was rejected")
	if client.set_local_test_endpoint("https://example.com"):failures.append("Non-loopback test endpoint was accepted")
	if not client.set_session_key("sk-test-12345678901234567890"):failures.append("Fixture credential was rejected")
	if client.configure("gpt-5.4-mini",64,3,5,true)!=OK:failures.append("Settings did not save")
	var status: Dictionary=await client.test_connection()
	if not status.get("ok",false):failures.append("Model connection check failed: "+str(status.get("error","")))
	var response: Dictionary=await client.respond("test prompt")
	if not response.get("ok",false) or response.get("text","")!="fixture answer":failures.append("Responses API request failed: "+str(response.get("error","")))
	var too_long: Dictionary=await client.respond("x".repeat(4001))
	if too_long.get("ok",true):failures.append("Oversized prompt was accepted")
	if client.configure("rate-limited",64,3,5,true)!=OK:failures.append("Rate-limit test settings did not save")
	var limited: Dictionary=await client.test_connection()
	if limited.get("ok",true) or not str(limited.get("error","")).contains("rate limiting"):failures.append("HTTP 429 was not mapped safely")
	var capped: Dictionary=await client.test_connection()
	if capped.get("ok",true) or not str(capped.get("error","")).contains("per-minute"):failures.append("Per-minute limit did not stop another request")
	if client.configure("gpt-5.4-mini",64,10,4,true)!=OK:failures.append("Daily-limit settings did not save")
	if not client.set_session_key("sk-wrong-12345678901234567890"):failures.append("Invalid-key fixture was rejected locally")
	var unauthorized: Dictionary=await client.test_connection()
	if unauthorized.get("ok",true) or str(unauthorized.get("error","")).contains("secret details"):failures.append("HTTP 401 exposed API error details")
	var daily_capped: Dictionary=await client.test_connection()
	if daily_capped.get("ok",true) or not str(daily_capped.get("error","")).contains("daily"):failures.append("Daily limit did not stop another request")
	if FileAccess.get_file_as_string("user://host_openai.cfg").contains("sk-test-"):failures.append("Credential was written to settings")
	client.clear_session_key()
	if client.configured():failures.append("Session credential was not removed")
	var reloaded: Node=Client.new();root.add_child(reloaded)
	if reloaded.used_today!=4 or reloaded.requests_per_day!=4:failures.append("Daily request count did not survive a restart")
	reloaded.set_session_key("sk-test-12345678901234567890")
	var persisted_limit: Dictionary=await reloaded.test_connection()
	if persisted_limit.get("ok",true) or not str(persisted_limit.get("error","")).contains("daily"):failures.append("Persisted daily cap was bypassed")
	if OS.get_environment("LABVOLT_TEST_OPENAI_TLS")=="1":
		var probe:=HTTPRequest.new();root.add_child(probe);probe.timeout=15.0
		if probe.request("https://api.openai.com/v1/models/gpt-5.4-mini")!=OK:failures.append("Could not start OpenAI TLS probe")
		else:
			var probe_result: Array=await probe.request_completed
			if int(probe_result[0])!=HTTPRequest.RESULT_SUCCESS or int(probe_result[1])!=401:failures.append("OpenAI TLS probe did not receive the expected authentication response")
		probe.queue_free()
	for failure in failures:push_error(failure)
	print("HOST_OPENAI ","PASS" if failures.is_empty() else "FAIL (%d)"%failures.size())
	quit(0 if failures.is_empty() else 1)
