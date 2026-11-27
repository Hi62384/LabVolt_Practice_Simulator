extends SceneTree
## Native layout geometry at the gameplay viewport. This does not substitute
## for pixel screenshots or physical pointer/audio testing.
const Settings=preload("res://scripts/campus/ui/settings_page.gd")
const Studio=preload("res://scripts/campus/ui/character_voice_studio.gd")
var failures: Array[String]=[]

func _initialize() -> void:run.call_deferred()

func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)

func check_rows(parent: Node,caption: String) -> void:
	for child in parent.get_children():
		if child is HBoxContainer and child.is_visible_in_tree():
			for control in child.get_children():
				if control is Control and control.visible:
					check(control.position.x>=-.5 and control.position.x+control.size.x<=child.size.x+.5,"%s row clips %s: x=%s width=%s row=%s"%[caption,control.get_class(),control.position.x,control.size.x,child.size.x])
		check_rows(child,caption)

func run() -> void:
	root.size=Vector2i(1280,720)
	# Embed the actual popup so its Controls use the gameplay viewport.
	root.gui_embed_subwindows=true
	var game: Node=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for frame in 4:await process_frame
	var page:=Settings.new();root.add_child(page);page.build(game);page._select("Audio")
	for frame in 3:await process_frame
	var scroller: ScrollContainer=page.body.get_parent()
	check(page.size==Vector2(1280,720),"Audio settings fill the 1280x720 viewport")
	check(page.body.size.x<=scroller.size.x+.5,"Audio settings do not require hidden horizontal scrolling")
	check_rows(page.body,"Audio")
	check(scroller.get_v_scroll_bar().max_value>scroller.size.y,"Long audio settings remain vertically scrollable")
	scroller.scroll_vertical=int(scroller.get_v_scroll_bar().max_value)
	await process_frame
	var last: Control=page.body.get_child(page.body.get_child_count()-1)
	check(last.get_global_rect().end.y<=scroller.get_global_rect().end.y+1.,"Audio diagnostics control is reachable at the bottom of the page")
	var audio_geometry:={"page":page.size,"body":page.body.size,"viewport":scroller.size}
	page.queue_free();await process_frame
	var window:=Window.new();window.min_size=Vector2i(720,460);window.size=Vector2i(1060,660);root.add_child(window)
	var outer:=ScrollContainer.new();outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);outer.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;window.add_child(outer)
	var studio:=Studio.new();studio.size_flags_horizontal=Control.SIZE_EXPAND_FILL;outer.add_child(studio)
	studio.configure(game.host_openai,{"modalities":{"tts":"gpt-realtime-2.1-mini"}})
	window.popup_centered(window.size)
	# The Dummy display driver reports no usable desktop rectangle, so popup
	# placement clamps even embedded windows to min_size. Measure the real
	# controls at the intended size explicitly; desktop placement is not tested.
	window.size=Vector2i(1060,660)
	for frame in 3:await process_frame
	check(window.size==Vector2i(1060,660),"Character Voices preserves the requested audition window size")
	check(studio.size.x<=outer.size.x+.5,"Character Voices fits its 1060px audition window")
	check(studio.character_list.size.x>=180. and studio.character_list.size.y>=300.,"Searchable character list has readable stable dimensions")
	check_rows(studio,"Character Voices")
	for id: String in ["mr_bro","dr_volts","ms_bird_heart"]:
		studio._select(id)
		await process_frame
		check(studio.identity_label.get_minimum_size().y<=studio.identity_label.size.y+.5,"Voice identity details fit for "+id)
	var nominal_geometry:={"window":window.size,"content":studio.size,"list":studio.character_list.size,"identity":studio.identity_label.size}
	window.size=Vector2i(720,460)
	for frame in 3:await process_frame
	check_rows(studio,"Character Voices minimum window")
	var split: HBoxContainer=studio.get_child(2)
	var details_scroller: ScrollContainer=split.get_child(1)
	details_scroller.scroll_vertical=int(details_scroller.get_v_scroll_bar().max_value)
	outer.scroll_vertical=int(outer.get_v_scroll_bar().max_value)
	await process_frame
	check(studio.generate_button.get_global_rect().end.y<=outer.get_global_rect().end.y+1.,"Character Voices allocation action remains reachable at minimum size")
	var studio_geometry:={"window":window.size,"content":studio.size,"list":studio.character_list.size,"identity":studio.identity_label.size}
	print("VOICE_SETTINGS_LAYOUT ","PASS" if failures.is_empty() else "FAIL", " audio=",audio_geometry," studio=",nominal_geometry," minimum=",studio_geometry," (native geometry; screenshots unavailable)")
	window.queue_free();game.queue_free();await process_frame;await process_frame
	quit(0 if failures.is_empty() else 1)
