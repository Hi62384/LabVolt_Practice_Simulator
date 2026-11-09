extends RefCounted
## Keeps a visible row tied to the real stock identity across inventory refreshes.
var rows: Array = []
var selected_type := ""
var selected_instance := ""

func refresh(next_rows: Array) -> void:
	rows = next_rows.duplicate(true)
	if selected_type.is_empty():return
	for row in rows:
		if str(row.type) == selected_type and str(row.instance_id) == selected_instance and int(row.quantity) > 0:return
	selected_type = "";selected_instance = ""

func choose(type_id: String, instance_id: String = "") -> bool:
	for row in rows:
		if str(row.type) == type_id and str(row.instance_id) == instance_id and int(row.quantity) > 0:
			selected_type = type_id;selected_instance = instance_id;return true
	return false

func current() -> Dictionary:
	for row in rows:
		if str(row.type) == selected_type and str(row.instance_id) == selected_instance:return row.duplicate(true)
	return {}

## Call before validating/saving a changed board. Existing bindings survive; a
## newly placed part receives the selected owned ID, if still unclaimed.
func bind_new_parts(board: Dictionary, previous: Dictionary) -> String:
	var present := {}
	for part in previous.get("parts", []):
		if part is Dictionary:present[str(part.get("id", ""))] = true
	var bindings: Dictionary = board.get("instance_ids", {}).duplicate(true)
	var live := {}
	for part in board.get("parts", []):
		if part is Dictionary:live[str(part.get("id", ""))] = true
	for id in bindings.keys():
		if not live.has(id):bindings.erase(id)
	if selected_type.is_empty():board.instance_ids = bindings;return ""
	for part in board.get("parts", []):
		if not part is Dictionary or present.has(str(part.get("id", ""))) or str(part.get("type", "")) != selected_type:continue
		var selected := current()
		if selected.is_empty():return "Selected component is no longer available"
		if selected_instance.is_empty():continue
		if selected_instance in bindings.values():return "That component is already on this board"
		bindings[str(part.id)] = selected_instance
	board.instance_ids = bindings
	return ""
