extends SceneTree

const Editor=preload("res://scripts/campus/computers/monaco_surface.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var surface:=Editor.new()
	root.add_child(surface)
	surface.size=Vector2(820,560)
	if not surface.start():
		_fail("Could not start the graphical Code Editor.")
		return
	var source:="import { campusName } from './settings';\nconst result: number = campusName;\n"
	surface.show_source("Projects/main.ts",source,{"Projects/settings.ts":"export const campusName: string = 'Campus';"})
	for attempt in 100:
		if surface.initialized:break
		await create_timer(.1).timeout
	if not surface.initialized:
		_fail("The editor did not initialize.")
		return
	surface.browser.execute_javascript("""
		require(['vs/language/typescript/monaco.contribution'], async service => {
			try {
				const uri = monaco.Uri.file('/campus-workspace/Projects/main.ts');
				const getWorker = await service.getTypeScriptWorker();
				const worker = await getWorker(uri);
				const diagnostics = await worker.getSemanticDiagnostics(uri.toString());
				document.title = diagnostics.map(diagnostic => diagnostic.code).join(',');
			} catch (error) {
				document.title = 'Worker failed: ' + error.message;
			}
		});
	""")
	for attempt in 100:
		var title: String=surface.browser.get_title()
		# TS2322 proves the imported value resolved to string. An unresolved
		# sibling produces TS2307 instead and cannot provide cross-file types.
		if title=="2322":
			print("IDE_PROJECT_SYMBOLS PASS")
			surface.queue_free()
			await process_frame
			quit()
			return
		if title.begins_with("Worker failed"):break
		await create_timer(.1).timeout
	_fail("Unexpected TypeScript diagnostics: "+str(surface.browser.get_title()))

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
