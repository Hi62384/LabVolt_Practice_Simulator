extends SceneTree

const Client=preload("res://scripts/campus/ai/host_openai_client.gd")
var failures: Array[String]=[]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var legacy_settings:=ConfigFile.new()
	legacy_settings.set_value("openai","requests_per_minute",1)
	legacy_settings.set_value("openai","requests_per_day",1)
	legacy_settings.save("user://host_openai.cfg")
	var client: Node=Client.new()
	root.add_child(client)
	if not client.set_local_test_endpoint("http://127.0.0.1:28768/v1"):failures.append("Test endpoint was rejected")
	if client.set_local_test_endpoint("https://example.com"):failures.append("Non-loopback test endpoint was accepted")
	if not client.set_session_key("sk-test-12345678901234567890"):failures.append("Fixture credential was rejected")
	if client.configure("gpt-5.4-mini",64,"",true)!=OK:failures.append("Settings did not save")
	var status: Dictionary=await client.test_connection()
	if not status.get("ok",false):failures.append("Model connection check failed: "+str(status.get("error","")))
	for attempt in 25:
		var response: Dictionary=await client.respond("test prompt")
		if response.get("text","")!="fixture answer":
			failures.append("OpenAI request %d failed: %s"%[attempt+1,response.get("error","")])
			break
	var too_long: Dictionary=await client.respond("x".repeat(4001))
	if too_long.get("ok",true):failures.append("Oversized prompt was accepted")
	if client.configure("rate-limited",64,"",true)!=OK:failures.append("Rate-limit test settings did not save")
	var limited: Dictionary=await client.test_connection()
	if limited.get("ok",true) or not str(limited.get("error","")).contains("rate limiting"):failures.append("HTTP 429 was not mapped safely")
	if client.configure("gpt-5.4-mini",64,"",true)!=OK:failures.append("Settings did not save")
	if not client.set_session_key("sk-wrong-12345678901234567890"):failures.append("Invalid-key fixture was rejected locally")
	var unauthorized: Dictionary=await client.test_connection()
	if unauthorized.get("ok",true) or str(unauthorized.get("error","")).contains("secret details"):failures.append("HTTP 401 exposed API error details")
	if FileAccess.get_file_as_string("user://host_openai.cfg").contains("sk-test-"):failures.append("Credential was written to settings")
	client.clear_session_key()
	if client.configured():failures.append("Session credential was not removed")
	var reloaded: Node=Client.new();root.add_child(reloaded)
	var totals: Dictionary=reloaded.model_usage.get("gpt-5.4-mini",{})
	if totals.get("requests")!=25 or totals.get("input")!=250 or totals.get("output")!=500 or totals.get("reasoning")!=200:failures.append("Per-model usage did not survive a restart")
	reloaded.set_local_test_endpoint("http://127.0.0.1:28768/v1")
	reloaded.configure("gpt-5.4-mini",64,"",false)
	var draft: Dictionary={"key":"sk-test-12345678901234567890","model":"gpt-6.2-astra","output":64,"effort":"max"}
	var key_check: Dictionary=await reloaded.list_models(draft.key)
	if not key_check.get("ok",false) or reloaded.enabled or reloaded.configured():failures.append("Model discovery changed the live host settings")
	var models: Array=key_check.get("models",[])
	for id in ["gpt-6.2-astra","ft:gpt-4.1-mini-2025-04-14:local:custom:id","text-embedding-3-small","fixture-future-model"]:
		if id not in models:failures.append("Model discovery missed "+id)
	var preview: Dictionary=await reloaded.preview_setup_prompt("test prompt",draft)
	if preview.get("text","")!="fixture answer" or reloaded.enabled:failures.append("Draft prompt could not run before accepting settings")
	if reloaded.accept_setup(draft,str(preview.get("signature","")))!=OK or not reloaded.verified_for_class():failures.append("Accept did not activate the verified settings")
	if reloaded.reasoning_effort!="max":failures.append("Accept lost the thinking effort")
	if reloaded.configure("gpt-6.2-astra",64,"none",true)!=ERR_INVALID_PARAMETER:failures.append("Unsupported thinking effort was accepted")
	if reloaded.configure("gpt-3.5-turbo",64,"",true)!=OK:failures.append("Legacy chat model could not be selected")
	var legacy_response: Dictionary=await reloaded.respond("test prompt")
	if legacy_response.get("text","")!="legacy answer":failures.append("Legacy chat model did not answer")
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
