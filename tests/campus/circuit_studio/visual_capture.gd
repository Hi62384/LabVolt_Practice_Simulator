extends SceneTree

func _initialize() -> void:call_deferred("_run")

func _run() -> void:
	var scene:=load("res://scenes/Main.tscn") as PackedScene
	if scene==null:quit(1);return
	var game:=scene.instantiate();root.add_child(game)
	for i in 12:await process_frame
	game.front.screen.hide()
	game.front.body.hide()
	game.campus.streamer.clear_menu_rooms()
	game.campus.streamer.set_viewer_position(Vector3(26,5,47))
	game.campus.streamer.set_process(false)
	game.circuit_studio.room.show()
	game.player.enabled=false
	game.set_process(false);game.set_physics_process(false)
	game.player.set_process(false);game.player.set_physics_process(false)
	game.camera.current=true
	game.camera.global_position=Vector3(26,6.4,44.0)
	game.camera.look_at(Vector3(26,5.8,48.0),Vector3.UP)
	for i in 8:await process_frame
	game.circuit_studio.room.show()
	for i in 2:await process_frame
	print("STUDIO_VIEW_STATE ",game.camera.global_position," ",game.circuit_studio.room.global_position," ",game.circuit_studio.room.visible," ",game.circuit_studio.room.station_anchors.assembly_table.global_position)
	var image:=root.get_viewport().get_texture().get_image()
	var path: String=ProjectSettings.globalize_path("user://invention_studio_visual.png")
	var error: Error=image.save_png(path)
	print("STUDIO_VISUAL ",path," ",error," ",image.get_size())
	var station: Node=game.circuit_studio.room.station_anchors.assembly_table
	game.circuit_studio.interact(station)
	var window: Window=game.circuit_studio.room.adapter.builder_window
	window.draft=preload("res://scripts/campus/facilities/circuit_studio/assembly_model.gd").empty()
	window._editor()
	for i in 5:await process_frame
	var editor_image:=window.get_texture().get_image()
	var editor_path: String=ProjectSettings.globalize_path("user://invention_editor_visual.png")
	var editor_error: Error=editor_image.save_png(editor_path)
	print("EDITOR_VISUAL ",editor_path," ",editor_error," ",editor_image.get_size())
	window._close()
	game.invention_world.set_process(false);game.invention_world.set_physics_process(false)
	game.invention_world.placed["visual"]={"pcb_voltage":{"A":4.9,"B":0.0},"pcb_inputs":[{"id":"a","name":"Switch","kind":"toggle"},{"id":"b","name":"Button","kind":"button"},{"id":"c","name":"Encoder","kind":"io_encoder"},{"id":"d","name":"Selector","kind":"io_selector"},{"id":"e","name":"Slider","kind":"io_slider"},{"id":"f","name":"Keypad","kind":"io_keypad"}]}
	var pcb_panel:=preload("res://scripts/campus/facilities/circuit_studio/assembly_pcb_panel.gd").new()
	game.invention_world.add_child(pcb_panel);pcb_panel.open_board(game,"visual")
	for i in 4:await process_frame
	var pcb_image:=pcb_panel.get_texture().get_image()
	var pcb_path: String=ProjectSettings.globalize_path("user://invention_pcb_panel_visual.png")
	var pcb_error: Error=pcb_image.save_png(pcb_path)
	print("PCB_PANEL_VISUAL ",pcb_path," ",pcb_error," ",pcb_image.get_size())
	pcb_panel._close();game.invention_world.placed.erase("visual")
	quit(0 if error==OK else 1)
