extends SceneTree
## Isolated runtime-owner fixture; run after applying hud_corner_patch.json.
const CampusHUD = preload("res://scripts/campus/ui/campus_hud.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for viewport_size in [Vector2i(480, 800), Vector2i(640, 480), Vector2i(800, 600), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3440, 1440)]:
		var viewport := SubViewport.new()
		viewport.size = viewport_size
		root.add_child(viewport)
		var layer := CanvasLayer.new()
		viewport.add_child(layer)
		var hud := CampusHUD.new()
		hud.position = Vector2(28, 128) # Mirrors front_menu's pre-add legacy offset.
		layer.add_child(hud)
		# Text matches the two badges reported in the user's screenshot.
		hud.location.text = "M102 · Shop / Kit Editor / Trading"
		hud.activity.text = "Freeplay ·"
		hud.location.get_parent().get_parent().show()
		hud.activity.get_parent().get_parent().show()
		await process_frame
		var room_card := (hud.location.get_parent().get_parent() as Control).get_global_rect()
		var mode_card := (hud.activity.get_parent().get_parent() as Control).get_global_rect()
		assert(room_card.position.x >= 8.0 and room_card.position.y >= 8.0, "Room badge top-left margin")
		assert(room_card.position.x <= 24.0 and room_card.position.y <= 24.0, "Legacy offset overridden")
		assert(mode_card.position.y < 120.0 and mode_card.position.x >= 8.0, "Mode badge remains near top edge")
		assert(room_card.end.x <= viewport_size.x - 8.0 and mode_card.end.x <= viewport_size.x - 8.0, "Badges fit viewport width")
		assert(not room_card.intersects(mode_card), "Room and mode badges do not overlap")
		viewport.queue_free()
		await process_frame
	print("Campus badge corner bounds PASS at six viewport sizes")
	quit()
