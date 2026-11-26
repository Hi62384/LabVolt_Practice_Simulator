extends SceneTree

const Web=preload("res://scripts/campus/computers/offline_web_surface.gd")
const Package=preload("res://scripts/campus/computers/application_package.gd")
const SAMPLE="res://tests/campus/computers/sample_apps/campus-notes.campusapp"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var files:={"index.html":"<!doctype html><script type='module' src='scripts/main.js'></script>".to_utf8_buffer(),
		"scripts/shared.js":"export const expected = 41;".to_utf8_buffer(),
		"scripts/main.js":"""import {expected} from './shared.js';
			const state = await (await fetch('/__campus__/state.json')).json();
			if (state.count !== expected) throw new Error('App data failed to load');
			const saved = await fetch('/__campus__/state.json', {method: 'PUT', body: JSON.stringify({count: expected + 1})});
			if (!saved.ok) throw new Error('App data failed to update');
			try {
				await fetch('http://127.0.0.1:28769/languages', {mode: 'no-cors'});
				document.title = 'Unexpected network access';
			} catch (error) {
				document.title = 'Offline project active';
			}
		""".to_utf8_buffer()}
	var surface:=Web.new()
	root.add_child(surface)
	surface.size=Vector2(640,480)
	if not surface.open_project("index.html",files,'{"count":41}'):
		_fail("Unable to create the offline web surface")
		return
	if surface.browser.register_method("test_bridge",func():pass):
		_fail("Offline page unexpectedly registered a game bridge")
		return
	for attempt in 60:
		var title: String=surface.browser.get_title()
		if title=="Unexpected network access":
			_fail(title)
			return
		if title=="Offline project active" and surface.app_state()=='{"count":42}':
			surface.queue_free()
			await process_frame
			if not await _verify_notebook():return
			print("OFFLINE_APPS PASS")
			quit()
			return
		await create_timer(.1).timeout
	_fail("Unexpected title or state: "+str(surface.browser.get_title())+" / "+surface.app_state())

func _verify_notebook() -> bool:
	var package:=Package.open_package(FileAccess.get_file_as_bytes(SAMPLE))
	if package.has("error"):
		_fail(str(package.error))
		return false
	var notebook:=Web.new()
	root.add_child(notebook)
	notebook.size=Vector2(700,480)
	if not notebook.open_project(package.manifest.entry,package.assets,'{"note":"Previous note"}'):
		_fail("Could not open the sample app")
		return false
	for attempt in 60:
		notebook.browser.execute_javascript("""(() => {
			const field = document.getElementById('note');
			if (field && !field.disabled && field.value === 'Previous note') {
				field.value = 'New note';
				document.getElementById('notebook').requestSubmit();
			}
		})()""")
		await create_timer(.1).timeout
		if notebook.app_state()=='{"note":"New note"}':
			notebook.queue_free()
			await process_frame
			return true
	_fail("The sample app did not read and update its note: "+str(notebook.browser.get_title())+" / "+notebook.app_state())
	return false

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
