extends SceneTree
const Gym = preload("res://scripts/campus/facilities/gym_progress.gd")

func _initialize() -> void:
	var failures: Array[String] = []
	for exercise in Gym.exercise_data():
		var fresh: Dictionary = Gym.empty()
		var capacity: float = Gym.capacity(fresh, exercise)
		var body_load: float = Gym.effective_load(exercise, 0.0, 70.0)
		var weight := maxf(0.0, capacity * .90 - body_load)
		var first_time: int = Gym.movement_ms(fresh, exercise, weight, 1000)
		var reps := 0
		while reps < 500:
			if Gym.rep(fresh, exercise, weight).failure: break
			reps += 1
		if reps == 500: failures.append("No eventual failure: " + exercise)
		if body_load < capacity * .90 and reps == 0: failures.append("Manageable load failed immediately: " + exercise)
		if reps > 0 and Gym.movement_ms(fresh, exercise, weight, 1000) < first_time:
			failures.append("Fatigue sped up movement: " + exercise)
		for muscle in fresh.muscles:
			if not Gym.exercise_data()[exercise].muscles.has(muscle): failures.append("Unexpected muscle stimulus: " + exercise)
			if fresh.muscles[muscle].size != 0.0 or fresh.muscles[muscle].strength != 0.0:
				failures.append("Immediate growth: " + exercise)
	for message in failures: push_error(message)
	print("ALL_EXERCISE_FAILURE ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
