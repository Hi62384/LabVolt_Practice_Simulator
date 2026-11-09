extends SceneTree

const Desktop = preload("res://review_artifacts/m203_computer_classroom_20261107/desktop_ui/desktop_ui.gd")

class FakeSession extends Node:
	signal desktop_changed(snapshot: Dictionary)
	signal operation_failed(message: String)
	var requests: Array[Dictionary] = []
	func request(action: Dictionary) -> void:
		requests.append(action.duplicate(true))
	func supports_operation(op: String) -> bool:
		return op == "rename"

var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)

func _run() -> void:
	var a := FakeSession.new()
	var b := FakeSession.new()
	root.add_child(a)
	root.add_child(b)
	var ua: Control = Desktop.new()
	var ub: Control = Desktop.new()
	root.add_child(ua)
	root.add_child(ub)
	ua.build(a)
	ub.build(b)
	a.desktop_changed.emit({"lease": 10, "revision": 1, "station": "m203_r0_c0", "files": {"notes.txt": {"text": "Alice", "version": 2}}, "editor": {"path": "notes.txt"}})
	b.desktop_changed.emit({"lease": 11, "revision": 1, "station": "m203_r0_c1", "files": {"notes.txt": {"text": "Bob", "version": 1}}, "editor": {"path": "notes.txt"}})
	ua._switch_app("Text editor")
	ub._switch_app("Text editor")
	check(ua.editor.text == "Alice" and ub.editor.text == "Bob", "private documents displayed")
	ua.editor.text = "Alice draft"
	ua._on_text_changed()
	check(ua.drafts.get("notes.txt") == "Alice draft" and ub.drafts.is_empty(), "drafts isolated")
	ua._save_file()
	check(a.requests.size() == 1 and a.requests[0] == {"op": "save", "path": "notes.txt", "text": "Alice draft", "version": 2, "lease": 10, "revision": 1}, "authoritative save payload")
	check(b.requests.is_empty(), "no cross-session request")
	a.desktop_changed.emit({"lease": 10, "revision": 2, "station": "m203_r0_c0", "files": {"notes.txt": {"text": "Alice draft", "version": 3}}, "editor": {"path": "notes.txt"}})
	check(ua.drafts.is_empty(), "acknowledged draft cleared")
	ua._new_file()
	ua.path_field.text = "work/program.py"
	ua.editor.text = "print(1)"
	ua._save_file()
	check(a.requests.back().get("version") == 0 and a.requests.back().get("path") == "work/program.py", "new virtual file save")
	a.desktop_changed.emit({"lease": 10, "revision": 3, "station": "m203_r0_c0", "files": {"notes.txt": {"text": "Alice draft", "version": 3}, "work/program.py": {"text": "print(1)", "version": 1}}, "editor": {"path": "work/program.py"}})
	check(not ua.pending_new and ua.drafts.is_empty(), "new file acknowledged")
	ua.path_field.text = "work/renamed.py"
	ua._rename_file()
	check(a.requests.back().get("op") == "rename" and a.requests.back().get("lease") == 10 and a.requests.back().get("revision") == 3, "rename uses current lease and revision")
	a.desktop_changed.emit({"lease": 10, "revision": 4, "station": "m203_r0_c0", "files": {"notes.txt": {"text": "Alice draft", "version": 3}, "work/renamed.py": {"text": "print(1)", "version": 2}}, "editor": {"path": "work/renamed.py"}})
	check(ua.current_path == "work/renamed.py" and ua.pending_rename.is_empty(), "rename waits for acknowledgment")
	ua.editor.text = "private draft"
	ua._on_text_changed()
	a.desktop_changed.emit({"lease": 12, "revision": 0, "station": "m203_r1_c0", "files": {}, "editor": {}})
	check(ua.drafts.is_empty() and ua.current_path.is_empty(), "new lease discards prior private draft")
	ua._switch_app("Browser")
	check(a.requests.size() == 3, "browser does not execute")
	ua._switch_app("Text editor")
	ua._new_file()
	ua.editor.text = "unsaved"
	ua._on_text_changed()
	ua._request_exit()
	check(ua.discard_dialog.visible and a.requests.size() == 3, "unsaved exit asks before discarding")
	a.desktop_changed.emit({})
	check(not ua.visible and ua.snapshot.is_empty() and ua.editor.text.is_empty(), "exit clears private UI")
	if errors.is_empty():
		print("desktop_ui fixture PASS")
		quit(0)
	else:
		for error in errors:
			push_error(error)
		quit(1)
