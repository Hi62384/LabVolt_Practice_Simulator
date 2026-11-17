extends SceneTree
const Client=preload("res://scripts/campus/ai/host_openai_client.gd")
const Policy=preload("res://scripts/campus/ai/browser_assistant_policy.gd")

func _initialize() -> void:call_deferred("_run")

func _run() -> void:
	var client:=Client.new();root.add_child(client)
	var failures: Array[String]=[]
	if not client.set_local_test_endpoint("http://127.0.0.1:28768/v1") or not client.set_session_key("sk-test-12345678901234567890") or client.configure("gpt-5.4-mini",384,10,20,true)!=OK:failures.append("Fixture setup")
	var view:=Policy.page({"url":"https://example.com","title":"Example","text":"Visible lesson","targets":[]})
	var prompt:=Policy.prompt("Explain this page",view)
	var text_result: Dictionary=await client.respond(prompt)
	if not text_result.get("ok",false) or not str(text_result.get("text","")).contains("Page answer"):failures.append("Text response")
	var image_result: Dictionary=await client.respond_with_image(prompt,PackedByteArray([255,216,255,217]))
	if not image_result.get("ok",false) or not str(image_result.get("text","")).contains("Image answer"):failures.append("Image response")
	for failure in failures:push_error(failure)
	print("BROWSER_ASSISTANT_TRANSPORT ","PASS" if failures.is_empty() else "FAIL (%d)"%failures.size())
	quit(0 if failures.is_empty() else 1)
