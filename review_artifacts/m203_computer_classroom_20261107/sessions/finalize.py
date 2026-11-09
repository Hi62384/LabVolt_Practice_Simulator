from pathlib import Path
root=Path('review_artifacts/m203_computer_classroom_20261107/sessions')
p=root/'computer_sessions.gd';s=p.read_text();s=s.replace('func request(action: Dictionary) -> void:\n','''func request(action: Dictionary) -> void:
	if action.get("op","")=="exit" and game.get("player")!=null and game.player.seated!=null:
		game._stand_from_chair()
		if game.player.seated!=null:
			operation_failed.emit("Move clear of the desk before standing.")
			return
''');s=s.replace('func _reset() -> void:\n','func _reset() -> void:\n\tset_meta("resetting",true)\n');s=s.replace('\toccupancy_changed.emit({})\n','\toccupancy_changed.emit({})\n\tset_meta("resetting",false)\n');p.write_text(s)
p=root/'classroom_adapter.gd';s=p.read_text();s=s.replace('if ui_was_open and game.front.in_game:game.capture()','''if game.computers.get_meta("resetting",false):
			Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
			game.player.enabled=false
		elif ui_was_open and game.front.in_game:game.capture()''');p.write_text(s)
p=root/'check_sources.py';s=p.read_text().replace("assert 'Files.validate(files)' in session",'''assert 'Files.validate(files)' in session
assert 'game.school._public_project(paper.project' in session
assert 'packet.papers' not in session
assert 'game._stand_from_chair()' in session
assert 'game.release_mouse()' in (root/'classroom_adapter.gd').read_text()
assert 'ComputerSessions' in (root/'assembly_shared_patches.json').read_text()''').replace('15 source boundary','20 source boundary');p.write_text(s)
