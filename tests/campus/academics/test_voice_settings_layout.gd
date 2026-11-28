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

func check_studio_regions(studio: Control,outer: ScrollContainer,caption: String) -> void:
	var details: ScrollContainer=studio.detail_scroll
	check(studio.size.x<=outer.size.x+.5,caption+" fits without hidden horizontal scrolling")
	check(studio.character_list.size.x>=180. and studio.character_list.size.y>=160.,caption+" roster shows several readable selectable rows")
	check(details.size.x>=380. and details.size.y>=260.,caption+" has a usable independently scrollable detail area")
	check(not details.get_global_rect().intersects(studio.character_list.get_global_rect()),caption+" roster and details do not overlap")
	check(details.get_child(0).size.x<=details.size.x+.5,caption+" details wrap within the available width")
	check_rows(studio,caption)

func check_reachable(studio: Control,outer: ScrollContainer,control: Control,caption: String) -> void:
	studio.detail_scroll.ensure_control_visible(control)
	outer.ensure_control_visible(studio.detail_scroll)
	for frame in 2:await process_frame
	var visible_area:=outer.get_global_rect().intersection(studio.detail_scroll.get_global_rect()).grow(1.)
	check(visible_area.encloses(control.get_global_rect()),caption+" remains fully reachable by scrolling")

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
	check_studio_regions(studio,outer,"Character Voices")
	for id: String in ["mr_bro","dr_volts","ms_bird_heart"]:
		studio._select(id)
		await process_frame
		check(studio.identity_label.get_minimum_size().y<=studio.identity_label.size.y+.5,"Voice identity details fit for "+id)
	var nominal_geometry:={"window":window.size,"content":studio.size,"list":studio.character_list.size,"identity":studio.identity_label.size}
	var roster_rect: Rect2=studio.character_list.get_global_rect()
	await check_reachable(studio,outer,studio.preview_button,"Audition action")
	check(studio.character_list.get_global_rect()==roster_rect,"Roster stays fixed while voice details scroll")
	window.size=Vector2i(720,460)
	for frame in 3:await process_frame
	check_studio_regions(studio,outer,"Character Voices minimum window")
	for action in [studio.generate_button,studio.preview_button,studio.approve_button,studio.advanced_toggle]:
		await check_reachable(studio,outer,action,"Character Voices "+action.text)
	studio.advanced_toggle.button_pressed=true
	for frame in 3:await process_frame
	await check_reachable(studio,outer,studio.batch_button,"Advanced allocation action")
	var studio_geometry:={"window":window.size,"content":studio.size,"list":studio.character_list.size,"identity":studio.identity_label.size}
	print("VOICE_SETTINGS_LAYOUT ","PASS" if failures.is_empty() else "FAIL", " audio=",audio_geometry," studio=",nominal_geometry," minimum=",studio_geometry," (native geometry; screenshots unavailable)")
	window.queue_free();game.queue_free();await process_frame;await process_frame
	quit(0 if failures.is_empty() else 1)
