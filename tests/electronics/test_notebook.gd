extends SceneTree
func _initialize():call_deferred("run")
func run():
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 5:await process_frame
	game.front.in_game=true;game.school.start("Freeplay",0)
	game.electronics.open("notes",1)
	await game.electronics.open_notebook()
	assert(game.school.papers.size()==1)
	var id=game.school.papers.keys()[0]
	assert(game.school.papers[id].notebook)
	game.school.request({"op":"page","id":id,"page":2})
	game.school.request({"op":"stroke","id":id,"page":2,"points":[Vector2(.1,.2),Vector2(.3,.4)],"color":"123456","width":3.0})
	game.electronics.save_notebook()
	var store=load("res://scripts/notebook_store.gd")
	var saved=store.read(game.characters.selected)
	assert(saved.page==2 and saved.strokes["2"].size()==1)
	assert(store.read("different-character").is_empty())
	game.school.papers.clear()
	game.school.request({"op":"notebook"})
	var restored=game.school.papers.values()[0]
	assert(restored.page==2 and restored.strokes==saved.strokes)
	print("PASS: notebook manager opens paper, page and ink persist, character isolation, reopened notebook restores content")
	quit()
