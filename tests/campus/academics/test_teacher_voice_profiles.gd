extends SceneTree
const Profiles=preload("res://scripts/campus/academics/teacher_voice_profiles.gd")
const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")
func _initialize() -> void:
	var entries:=Profiles.profiles()
	if entries.size()!=21 or entries.size()!=Roster.PEOPLE.size():push_error("Invalid profile roster: "+str(entries.size()));quit(1);return
	for id in Profiles.available_voice_ids():
		if not entries.has(id):push_error("Unknown local voice identity");quit(1);return
	if not entries.brian.target.contains("angry") or not entries.ms_bird_heart.target.contains("female"):push_error("Profile descriptions missing");quit(1);return
	print("TEACHER_VOICE_PROFILES PASS (legacy profiles remain explicitly available)")
	quit(0)
