extends RefCounted
## Compare only visible supply quantities; never inspect or mutate solver internals.
const Budget = preload("res://scripts/campus/performance/equipment_budget.gd")
var budget := Budget.new()
var _signatures := {}
var _states := {}
var _targets := {}

func observe(id: String, state: Dictionary, target: Label3D, relevant := true) -> void:
	if not is_instance_valid(target):
		return
	if not _targets.has(id):
		var adapter_ref: WeakRef = weakref(self)
		budget.register_display(id, func():
			var adapter: RefCounted = adapter_ref.get_ref()
			if adapter != null:
				adapter._refresh(id)
		, 10.0)
	if not _targets.has(id) or _targets[id].get_ref() != target:
		_targets[id] = weakref(target)
		budget.mark_dirty(id)
	var result: Dictionary = state.get("result", {})
	var signature: Array = []
	for i in 3:
		var channel := "s%d" % i
		signature.append(float(result.get("drop", {}).get(channel, 0)))
		signature.append(float(result.get("i", {}).get(channel, 0)))
		signature.append(str(result.get("mode", {}).get(channel, "OFF")))
	if _signatures.get(id, []) != signature:
		_signatures[id] = signature
		_states[id] = signature
		budget.mark_dirty(id)
	budget.set_relevant(id, relevant)

func tick(delta: float, budget_usec := 500) -> int:
	return budget.tick(delta, budget_usec)

func _refresh(id: String) -> void:
	var label: Label3D = _targets[id].get_ref()
	if not is_instance_valid(label):
		budget.unregister_display(id)
		_targets.erase(id)
		_states.erase(id)
		_signatures.erase(id)
		return
	var values: Array = _states.get(id, [])
	if values.size() != 9:
		return
	var text := ""
	for i in 3:
		text += "CH%d  %5.2f V  %5.3f A  %s\n" % [i+1, values[i*3], -float(values[i*3+1]), values[i*3+2]]
	if label.text != text:
		label.text = text

func clear() -> void:
	for id in _targets.keys():
		budget.unregister_display(id)
	_targets.clear()
	_states.clear()
	_signatures.clear()
