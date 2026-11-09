extends RefCounted
## Optional envelope boundary for the host paper adapter. Does not authorize a peer.
const Notation = preload("res://scripts/math_ui/math_notation.gd")
const MAX_BYTES = 65536
const STATE_KEYS = ["version","question_id","answer","inputs","page","drawing","view","reference_section","complex_form","angle_unit","classification"]

static func encode(state: Dictionary) -> Dictionary:
	if not Notation.json_safe(state):return {"ok":false,"error":"Invalid mathematics state."}
	var text:=JSON.stringify(state)
	if text.to_utf8_buffer().size()>MAX_BYTES:return {"ok":false,"error":"Mathematics page exceeds save limit."}
	return {"ok":true,"text":text}

static func decode(text: String, question_id: String) -> Dictionary:
	if text.to_utf8_buffer().size()>MAX_BYTES:return {"ok":false,"error":"Mathematics page exceeds save limit."}
	var state:Variant=JSON.parse_string(text)
	if not state is Dictionary or not Notation.json_safe(state):return {"ok":false,"error":"Invalid mathematics state."}
	if int(state.get("version",0))!=1 or str(state.get("question_id",""))!=question_id:return {"ok":false,"error":"Wrong question or state version."}
	if not state.has("answer"):return {"ok":false,"error":"Missing structured answer."}
	for key in state:
		if key not in STATE_KEYS:return {"ok":false,"error":"Unexpected state field."}
	return {"ok":true,"answer":state.answer,"state":state}
