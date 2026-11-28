extends SceneTree

const Settings=preload("res://scripts/campus/ui/openai_settings.gd")
const Client=preload("res://scripts/campus/ai/host_openai_client.gd")
const ThemeBuilder=preload("res://scripts/ui/design_system/theme.gd")

class Host extends Node:
	var host_openai=Client.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(20).timeout.connect(func():quit(1))
	root.size=Vector2i(1260,760)
	var host:=Host.new()
	root.add_child(host)
	host.host_openai._environment_key_disconnected=true
	host.add_child(host.host_openai)
	var settings:=Settings.new()
	settings.theme=ThemeBuilder.create()
	root.add_child(settings)
	settings.build(host,func(_message: String):pass,func():pass)
	settings.model_ids=["gpt-6.2-astra","gpt-6.2-sol","gpt-5.4-mini","gpt-4.1-mini"]
	var profile: String=host.host_openai.usage_scope(settings._read_draft())
	host.host_openai.usage_tracker.rows={"fixture":{"model":"gpt-6.2-astra","profile":profile,"requests":4}}
	settings._open_picker("Text model","text")
	await process_frame
	assert(not settings.picker_models.has("gpt-4.1-mini"))
	settings.show_advanced.button_pressed=true
	settings._refresh_picker()
	for effort in [0,3,5,6,7]:
		settings.preview_effort.select(effort)
		settings._refresh_picker()
		var astra: Dictionary=settings.picker_models["gpt-6.2-astra"].measurement
		assert(astra.score_percent==97.)
		assert(astra.get("reference",false)==(effort!=0))
		var mini: Dictionary=settings.picker_models["gpt-5.4-mini"].measurement
		assert(mini.score_percent==88.)
		assert(mini.get("reference",false)==(effort not in [0,6]))
		assert(not settings.picker_models["gpt-4.1-mini"].measurement.has("score_percent"))
	settings.preview_effort.select(3)
	settings._refresh_picker()
	await process_frame
	var card: Node=settings.model_rows.get_child(0)
	var bars:=card.find_children("*","ProgressBar",true,false)
	assert(bars.size()==6)
	assert(bars[0].value==97. and bars[0].max_value==100.)
	assert(bars[1].value==0.)
	assert(bars[2].value==8. and bars[3].value==40.)
	assert(bars[4].value>0. and bars[5].value==4.)
	var capture:=OS.get_environment("LABVOLT_MODEL_PICKER_CAPTURE")
	if not capture.is_empty():
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(capture)==OK)
	print("OPENAI_MODEL_PICKER PASS")
	quit()
