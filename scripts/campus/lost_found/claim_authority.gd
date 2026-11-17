extends RefCounted

# This endpoint must be the same for every host. Personal room relays are not shared authority.
static func endpoint() -> String:
	var override:=OS.get_environment("LABVOLT_CLAIM_AUTHORITY_URL").strip_edges()
	return (override if not override.is_empty() else str(ProjectSettings.get_setting("network/labvolt/claim_authority_url", ""))).trim_suffix("/")

static func claim(owner: Node,token: String) -> Dictionary:
	return await _send(owner,token,HTTPClient.METHOD_POST)

static func status(owner: Node,token: String) -> Dictionary:
	return await _send(owner,token,HTTPClient.METHOD_GET)

static func reserve(owner: Node,token: String,holder: String) -> Dictionary:
	return await _send(owner,token,HTTPClient.METHOD_POST,"reserve",holder)

static func commit(owner: Node,token: String,holder: String) -> Dictionary:
	return await _send(owner,token,HTTPClient.METHOD_POST,"commit",holder)

static func release(owner: Node,token: String,holder: String) -> Dictionary:
	return await _send(owner,token,HTTPClient.METHOD_POST,"release",holder)

static func _send(owner: Node,token: String,method: int,operation := "",holder := "") -> Dictionary:
	if token.length()!=32 or not token.is_valid_hex_number():return {"ok":false,"error":"Invalid claim token."}
	if not operation.is_empty() and (holder.length()!=32 or not holder.is_valid_hex_number()):return {"ok":false,"error":"Invalid claim holder."}
	var base:=endpoint()
	if base.is_empty():return {"ok":false,"error":"Shared lost-and-found service is unavailable."}
	if not base.begins_with("https://") and not (OS.is_debug_build() and base.begins_with("http://127.0.0.1:")):
		return {"ok":false,"error":"Shared lost-and-found service must use HTTPS."}
	var request:=HTTPRequest.new()
	owner.add_child(request)
	request.timeout=8.0
	var headers: Array[String]=["Authorization: Bearer "+token]
	if not holder.is_empty():headers.append("X-Claim-Holder: "+holder)
	var url:=base+"/v1/claims/"+token.sha256_text()+("/"+operation if not operation.is_empty() else "")
	var code:=request.request(url,headers,method)
	if code!=OK:
		request.queue_free()
		return {"ok":false,"error":"Shared lost-and-found service is unavailable."}
	var response: Array=await request.request_completed
	request.queue_free()
	if int(response[0])!=HTTPRequest.RESULT_SUCCESS:return {"ok":false,"error":"Shared lost-and-found service is unavailable."}
	if method==HTTPClient.METHOD_GET:
		if int(response[1])==200:return {"ok":true,"claimed":true}
		if int(response[1])==404:return {"ok":true,"claimed":false}
		if int(response[1])==423:return {"ok":false,"reserved":true,"error":"Another pickup is in progress."}
	elif not operation.is_empty():
		if int(response[1])==200:return {"ok":true}
		if int(response[1])==423:return {"ok":false,"reserved":true,"error":"Another pickup is in progress."}
		if int(response[1])==409:return {"ok":false,"claimed":true,"error":"This item was already claimed."}
	else:
		if int(response[1])==201:return {"ok":true}
		if int(response[1])==409:return {"ok":false,"claimed":true,"error":"This item was already claimed on another host."}
	return {"ok":false,"error":"Shared lost-and-found service refused the claim."}
