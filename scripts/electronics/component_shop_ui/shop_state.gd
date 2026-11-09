extends RefCounted
## Presentation state only. Rating parsing, prices and purchase authority belong
## to the canonical component service and host ledger, never this object.
var selected_id := ""
var family := "All"
var search := ""
var quantity_text := "1"
var fields := {}
var pending_id := ""
var pending_selection := ""
var confirmation := {}
var sequence := 0

static func quantity_error(text: String) -> String:
	var result := preload("res://scripts/electronics/component_values/values.gd").quantity(text)
	return "" if result.ok else str(result.error)

func invalidate_confirmation() -> void:
	confirmation.clear()

func begin_request() -> String:
	if not pending_id.is_empty():return ""
	sequence+=1
	pending_id="component-shop-%d-%d"%[Time.get_ticks_usec(),sequence]
	pending_selection=selected_id
	return pending_id

func finish_request(id: String) -> bool:
	if id.is_empty() or id!=pending_id:return false
	pending_id="";pending_selection="";confirmation.clear()
	return true
