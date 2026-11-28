extends SceneTree
const Brain = preload("res://scripts/campus/academics/teacher_brain.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var neutral := {"difficulty": 0.5, "focus": 0.5, "talkativeness": 0.5, "traits": {"patience": 0.5, "anger_sensitivity": 0.5, "confrontation": 0.5, "discipline": 0.5, "empathy": 0.5}}
	var old_description := neutral.duplicate(true)
	old_description.description = "short temper military bearing friendly jokes warm encouragement disengagement"
	var renamed_description := neutral.duplicate(true)
	renamed_description.description = "Entirely different prose about the same individual."
	var first := Brain.new()
	var second := Brain.new()
	_check(first.consider("person_a", "player", "voice_noise", 0.6, old_description, 100000, 0.0) == second.consider("person_a", "player", "voice_noise", 0.6, renamed_description, 100000, 0.0), "Changing descriptive wording must not change local reaction selection")
	_check(first.teachers == second.teachers, "Local frustration must use numeric traits, not descriptor keywords")
	var attentive := neutral.duplicate(true)
	attentive.traits.merge({"attention_span": 1.0, "teaching_effort": 1.0, "laziness": 0.0}, true)
	var distracted := neutral.duplicate(true)
	distracted.traits.merge({"attention_span": 0.0, "teaching_effort": 0.0, "laziness": 1.0}, true)
	var noticed_attentive := 0
	var noticed_distracted := 0
	for index in 100:
		var roll := (float(index) + 0.5) / 100.0
		if not Brain.new().consider("observer", "player", "voice_noise", 0.4, attentive, 100000, roll).is_empty():
			noticed_attentive += 1
		if not Brain.new().consider("observer", "player", "voice_noise", 0.4, distracted, 100000, roll).is_empty():
			noticed_distracted += 1
	_check(noticed_attentive > noticed_distracted + 20, "Independent attention and motivation must materially affect routine perception")
	var impatient := neutral.duplicate(true)
	impatient.traits.merge({"patience": 0.0, "anger_sensitivity": 1.0, "confrontation": 1.0, "discipline": 1.0, "empathy": 0.0}, true)
	var patient := neutral.duplicate(true)
	patient.traits.merge({"patience": 1.0, "anger_sensitivity": 0.0, "confrontation": 0.0, "discipline": 0.0, "empathy": 1.0}, true)
	var reactive := Brain.new()
	var tolerant := Brain.new()
	var hot := reactive.consider("observer", "player", "voice_noise", 0.6, impatient, 100000, 0.0)
	var calm := tolerant.consider("observer", "player", "voice_noise", 0.6, patient, 100000, 0.0)
	_check(hot.get("level") == "firm" and calm.get("level") == "calm", "The same nuisance must permit different measured personality reactions")
	_check(reactive.teachers.observer.frustration > tolerant.teachers.observer.frustration, "Patience and anger sensitivity must affect accumulated frustration")
	var deaf := Brain.new()
	_check(deaf.consider("observer", "player", "voice_noise", 1.0, impatient, 100000, 0.0, 0.0).is_empty(), "Temper must never produce a reaction to an inaudible event")
	_check(deaf.incidents.is_empty() and deaf.relationships.is_empty(), "An inaudible event must not fabricate a recorded incident")
	_check(Brain.new().consider("observer", "player", "ambient_speech", 0.6, {"talkativeness": 0.0}, 100000, 0.0).is_empty(), "Zero social attention probability must stay zero even at the RNG boundary")
	_check(not Brain.new().consider("observer", "player", "lab_hazard", 1.0, distracted, 100000, 0.5, 1.0).is_empty(), "Disengaged attention must not suppress an audible serious laboratory hazard")
	_check(Brain.new().consider("observer", "player", "lab_hazard", 1.0, attentive, 100000, 0.5, 0.1).is_empty(), "Safety perception must still respect actual attenuation")
	var invalid := Brain.new()
	_check(invalid.consider("observer", "player", "voice_noise", NAN, neutral, 100000, 0.0).is_empty() and invalid.incidents.is_empty(), "Nonfinite event data must not enter local simulation")
	# Legacy numeric profiles retain their original classroom escalation behavior.
	var strict := Brain.new()
	var early := strict.consider("strict", "player", "class_message", 0.5, {"difficulty": 0.95, "focus": 0.9, "talkativeness": 0.5}, 100000, 0.0)
	var later: Dictionary = {}
	for index in 5:
		later = strict.consider("strict", "player", "class_message", 0.5, {"difficulty": 0.95, "focus": 0.9, "talkativeness": 0.5}, 113000 + index * 13000, 0.0)
	_check(early.get("level") == "calm" and later.get("level") == "firm", "Legacy numeric profiles must retain gradual repeated-disruption escalation")
	if failures.is_empty():
		print("TEACHER_NUMERIC_DISPOSITION PASS — independent traits, description invariance, attention, escalation, hearing authority")
	quit(0 if failures.is_empty() else 1)

func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
