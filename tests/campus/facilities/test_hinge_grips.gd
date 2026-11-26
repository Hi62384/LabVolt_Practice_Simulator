extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for frame in 4: await process_frame
	_press(game.front.body, "Singleplayer")
	await process_frame
	_press(game.front.body, "Play")
	await process_frame
	_check_hinge_grips(game)
	print("HINGE_GRIPS PASS")
	game.queue_free()
	await process_frame
	quit()

func _press(body: Control, label: String) -> void:
	for button in body.find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and button.text == label:
			button.pressed.emit()
			return
	assert(false, "Missing button " + label)

func _check_hinge_grips(game: Node) -> void:
	var bridge: Node = game.interaction_presentation
	var camera: Camera3D = game.camera
	var existing_bar: Node3D = game.gym_barbells.bar_hand
	var bar: Node3D = game.gym_barbells._bar_model("gym/barbell_rack_2")
	bar.scale = Vector3.ONE * .55
	camera.add_child(bar)
	game.gym_barbells.bar_hand = bar
	var existing_pair: Node3D = game.gym_weights.held_visual
	var pair: Node3D = game.gym_weights._pair_model(200.0)
	camera.add_child(pair)
	game.gym_weights.held_visual = pair
	assert(is_instance_valid(bar) and bridge.workout_arms.size() == 2)
	var floor_y: float = game.player.global_position.y
	for equipment in ["barbell", "dumbbell"]:
		for exercise in ["deadlift", "romanian_deadlift", "bent_over_row"]:
			bridge.workout_state = {"activity": "exercise", "exercise": exercise, "equipment": equipment, "workout_facing": 1.2}
			var bottom_height := 0.0
			for phase in [1.0, .5, 0.0]:
				bridge.workout_state.phase = phase
				bridge._update_workout(1.0)
				if equipment == "barbell":
					assert(absf(bar.global_basis.x.y) < .001, "Shaft tilted with the camera")
				for arm in bridge.workout_arms:
					var left: bool = arm.get_meta("workout_left", false)
					var side := -1.0 if left else 1.0
					var hand: Node3D = preload("res://scripts/campus/facilities/arm_bend.gd").hand_for(arm)
					var weight: Node3D = pair.get_node("LeftDumbbell" if left else "RightDumbbell")
					var grip: Vector3 = bar.to_global(Vector3(side * .35, 0, 0)) if equipment == "barbell" else weight.global_position
					assert(grip.y >= floor_y + .31, exercise + " put the grip too close to the floor")
					assert(grip.distance_to(hand.global_position) < .01, exercise + " separated the hand and grip")
				var height: float = bar.global_position.y if equipment == "barbell" else pair.get_child(0).global_position.y
				if phase == 1.0: bottom_height = height
				if phase == 0.0: assert(height > bottom_height + .45, exercise + " lost its lifting motion")
			bridge._clear_workout()
	game.gym_weights.held_visual = existing_pair
	pair.free()
	game.gym_barbells.bar_hand = existing_bar
	bar.free()
