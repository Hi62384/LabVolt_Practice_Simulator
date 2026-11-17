extends SceneTree
const Profiles=preload("res://scripts/campus/academics/teacher_voice_profiles.gd")
const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")
func _initialize() -> void:
	var entries:=Profiles.profiles()
	if entries.size()!=21 or entries.size()!=Roster.PEOPLE.size():push_error("Invalid profile roster: "+str(entries.size()));quit(1);return
	if not Profiles.available_voice_ids().is_empty():push_error("Unexpected local model");quit(1);return
	if not entries.brian.target.contains("angry") or not entries.ms_bird_heart.target.contains("female"):push_error("Profile descriptions missing");quit(1);return
	print("TEACHER_VOICE_PROFILES PASS (0 usable local models)")
	quit(0)
