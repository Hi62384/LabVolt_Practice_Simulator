extends SceneTree
const Provider = preload("res://scripts/campus/social/student_appearance/student_appearance_provider.gd")
const Core = preload("res://scripts/avatar_cosmetics/core/avatar_core.gd")
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _init() -> void:
	var provider := Provider.new(16)
	var first := provider.appearance_for_student("student-42", 701)
	check(first == provider.appearance_for_student("student-42", 701), "same identity rerolled")
	check(first == provider.appearance_from_packet(provider.network_packet("student-42", 701)), "packet reconstruction differs")
	var signatures := {}
	var silhouettes := {}
	for index in 80:
		var state := provider.appearance_for_student("student-%d" % index, 701)
		var body := Core.sanitize_body(state.body)
		for key in Core.BODY_FIELDS:
			check(float(body[key]) >= Core.BODY_MIN and float(body[key]) <= Core.BODY_MAX, "body value outside contract")
		for slot in state.equipped:
			check(slot in Core.SLOTS, "invalid slot " + slot)
			check(provider.catalog().has(state.equipped[slot].id), "unknown catalog item")
		signatures[JSON.stringify(state.equipped) + JSON.stringify(state.legacy_character)] = true
		silhouettes["%.2f|%.2f|%.2f|%.2f|%s" % [body.height, body.width, body.shoulders, body.leg_length, state.legacy_character.outfit]] = true
	check(signatures.size() >= 64, "appearance combinations are not meaningfully diverse")
	check(silhouettes.size() >= 48, "diversity is only color changes")
	check(provider.cache_size() <= 16, "cache exceeded configured bound")
	var mutated := provider.appearance_for_student("student-42", 701)
	mutated.body.height = 0.65
	check(provider.appearance_for_student("student-42", 701).body.height == first.body.height, "cached state leaked mutable data")
	check(first.legacy_character.size() > 0, "legacy renderer fallback missing")
	if failures.is_empty():
		print("PASS student appearance: deterministic, diverse, bounded, catalog-valid")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)
