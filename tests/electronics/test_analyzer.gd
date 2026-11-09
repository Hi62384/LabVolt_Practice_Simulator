extends SceneTree
func _initialize():
	var profile=load("res://scripts/electronics_profile.gd").new();profile.open("analyzer-"+str(Time.get_ticks_usec()))
	assert(profile.data.dollars==100)
	assert(profile.buy_analyzer().contains("unlocked"));assert(profile.data.dollars==25 and profile.data.analyzer)
	assert(profile.buy_analyzer().contains("already"));assert(profile.data.dollars==25)
	var again=load("res://scripts/electronics_profile.gd").new();again.path=profile.path
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(profile.path));assert(parsed.analyzer and parsed.dollars==25)
	profile.data.analyzer=false;assert(profile.buy_analyzer()=="Not enough dollars");assert(not profile.data.analyzer)
	profile.data.dollars=100;profile.data.pending_trade={"id":"test"};assert(profile.buy_analyzer().contains("pending"));assert(profile.data.dollars==100)
	print("PASS: analyzer purchase persists, charges once, rejects insufficient funds and pending trades")
	quit()
