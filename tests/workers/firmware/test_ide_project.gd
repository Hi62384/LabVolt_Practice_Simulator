extends SceneTree
var fails := 0
func check(ok: bool,message: String) -> void:
	print("PASS " if ok else "FAIL ",message)
	if not ok:fails+=1
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 6:await process_frame
	var kit: Dictionary=game.electronics.profile.data.kits.starter
	kit.items.lv_mcu=1;game.electronics.profile.data.inventory.lv_mcu=1
	kit.board.parts=[{"id":"mcu","type":"lv_mcu","a":"A1","b":"F1","pins":["A1","A2","A3","F1","F2","F3"]}]
	game.electronics.open("code")
	for i in 4:await process_frame
	var ide=game.electronics.body.get_child(0)
	check(ide.validate(),"legacy single-file IDE loads and validates")
	ide.files={"main.lvs":"#include \"setup.lvs\"\nwrite D0 1\nhalt","setup.lvs":"mode D0 out"}
	ide.active_file="main.lvs";ide.refresh_tabs();ide.editor.text=ide.files["main.lvs"]
	check(ide.file_tabs.tab_count==2,"IDE builds one tab per project file")
	ide.file_tabs.current_tab=1
	check(ide.active_file=="setup.lvs" and ide.editor.text=="mode D0 out","tab switch selects matching editor text")
	ide.editor.text="mode D0 in";ide.file_tabs.current_tab=0
	check(ide.files["setup.lvs"]=="mode D0 in","switching tabs preserves edits")
	ide.files["setup.lvs"]="mode D0 out";ide.upload()
	check(kit.board.parts[0].firmware=="mode D0 out\nwrite D0 1\nhalt","upload stores backward-compatible flattened firmware")
	check(kit.board.parts[0].code_files.size()==2,"source project files persist beside compiled firmware")
	game.electronics.open("code")
	for i in 3:await process_frame
	ide=game.electronics.body.get_child(0)
	check(ide.files.size()==2 and ide.files["setup.lvs"]=="mode D0 out","reopening IDE restores both source tabs")
	ide.files["setup.lvs"]="nonsense";check(not ide.validate(),"invalid included code rejected by IDE")
	check(ide.active_file=="setup.lvs" and ide.notice.text.begins_with("setup.lvs:1:"),"IDE selects file and line with diagnostic")
	ide.editor.text="mode D0 out";ide.remember()
	game.electronics.close();game.queue_free();await process_frame
	print("IDE PROJECT FAILURES: ",fails);quit(fails)
