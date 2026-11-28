extends SceneTree
## Actual OpenAI settings window + Character Voices controls, with offline
## service and synthetic saved students. No paid requests or voice-quality claim.
const Client=preload("res://scripts/campus/ai/host_openai_client.gd")
const Settings=preload("res://scripts/campus/ui/openai_settings.gd")
const People=preload("res://scripts/campus/academics/class_character_profile.gd")
const Voices=preload("res://scripts/campus/academics/teacher_voice_profiles.gd")
var failures: Array[String]=[]
var capture_path:=""

class PopulationFixture:
	extends RefCounted
	var people: Dictionary={}
	func profile_for(id: String) -> Dictionary:return people.get(id,{}).duplicate(true)

class GameFixture:
	extends Node
	var host_openai: Node
	var lecture_classes: Dictionary={}

func _initialize() -> void:_run.call_deferred()
func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)

func capture(window: Window,name: String) -> void:
	for frame in 5:await process_frame
	await RenderingServer.frame_post_draw
	var picture:=window.get_texture().get_image()
	check(picture!=null and not picture.is_empty(),"Actual rendered Studio framebuffer exists")
	if picture!=null and not picture.is_empty():check(picture.save_png(capture_path.path_join(name+".png"))==OK,"Saved "+name)

func _run() -> void:
	if DisplayServer.get_name()=="headless":push_error("Native display required");quit(2);return
	capture_path=OS.get_environment("LABVOLT_STUDIO_CAPTURE")
	if capture_path.is_empty():quit(2);return
	create_timer(40.).timeout.connect(func():push_error("Studio render timeout");quit(3))
	root.size=Vector2i(1280,720);root.gui_embed_subwindows=true
	var game:=GameFixture.new();root.add_child(game)
	game.host_openai=Client.new();game.host_openai._environment_key_disconnected=true;game.add_child(game.host_openai)
	var population:=PopulationFixture.new()
	for index in 2:
		var person:=People.legacy_student(index)
		person.id="campus_student_"+("studio-person-%d"%index).sha256_text().left(32)
		person.voice_scope="studio-origin".sha256_text()
		population.people[person.id]=person
	game.lecture_classes={"classroom_students":{"population":population}}
	var settings:=Settings.new();root.add_child(settings);settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings.build(game,func(_message: String):pass,func():pass)
	settings._open_voice_studio()
	var window: Window=settings.voice_studio
	var panel: Node=window.find_child("*",true,false)
	for node in window.find_children("*","VBoxContainer",true,false):
		if node.get_script()==load("res://scripts/campus/ui/character_voice_studio.gd"):panel=node;break
	for frame in 5:await process_frame
	check(panel.character_list.item_count==23,"Offline actual settings path lists all faculty and saved students")
	check(not panel.name_label.text.is_empty() and is_instance_valid(panel.portrait_model) and not panel.design.text.is_empty(),"Offline selection has real name, appearance and design")
	check(panel.voice_model.item_count>=7,"Speech model choices populated without a connection")
	check(panel.preview_button.disabled and panel.generate_button.disabled,"Only provider actions require credentials")
	check(not panel.advanced_box.visible,"Advanced recovery controls start collapsed")
	check(panel.preview_button.size.x>=100. and panel.core_button.size.x>=180. and panel.approve_button.size.x>=180.,"Flow action buttons have readable labels")
	await capture(window,"voice-studio-offline-1280")
	var left_rect: Rect2=panel.character_list.get_global_rect()
	panel.detail_scroll.scroll_vertical=440
	for frame in 5:await process_frame
	check(panel.character_list.get_global_rect()==left_rect,"Roster stays fixed while details scroll")
	await capture(window,"voice-studio-auditions-1280")
	panel.roster_filter.select(2);panel._fill_list()
	check(panel.character_list.item_count==2,"Student filter shows saved population")
	panel._select(str(panel.character_list.get_item_metadata(0)))
	panel.detail_scroll.scroll_vertical=0
	window.size=Vector2i(720,520)
	for frame in 5:await process_frame
	check(panel.detail_scroll.get_global_rect().end.x<=window.size.x,"Minimum-size details stay inside the window")
	check(panel.character_list.get_global_rect().size.y>100.,"Minimum-size roster remains usable")
	await capture(window,"voice-studio-student-720")
	var file:=FileAccess.open(capture_path.path_join("result.json"),FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify({"display":DisplayServer.get_name(),"adapter":RenderingServer.get_video_adapter_name(),"live_api":false,"audio_hardware":false,"failures":failures},"  "));file.close()
	settings.queue_free();game.queue_free();await process_frame
	print("VOICE_STUDIO_RENDER ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
