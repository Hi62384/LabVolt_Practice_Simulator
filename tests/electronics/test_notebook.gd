extends SceneTree
func _initialize():call_deferred("run")
func run():
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 5:await process_frame
	var route = game.front.body.find_children("*","Button",true,false).filter(func(button):return button.text=="Singleplayer")
	assert(route.size()==1)
	route[0].pressed.emit()
	await process_frame
	var play = game.front.body.find_children("*","Button",true,false).filter(func(button):return button.text=="Play")
	assert(play.size()==1)
	play[0].pressed.emit()
	for i in 5:await process_frame
	game.electronics.profile.data.dorm.supply_counts["notebook"]=1
	game.electronics.profile.data.dorm["carry_items"]=["notebook"]
	var store=load("res://scripts/notebook_store.gd")
	assert(store.write(game.characters.selected, {"page":0,"pages":3}))
	var legacy_uid: String=store.read(game.characters.selected).document_uid
	game.electronics.open("notes",1)
	await game.electronics.open_notebook()
	var notebooks = game.school.papers.values().filter(func(paper):return paper.get("notebook",false))
	assert(notebooks.size()==1)
	var id=notebooks[0].id
	assert(game.school.papers[id].notebook)
	game.school.request({"op":"page","id":id,"page":2})
	game.school.request({"op":"stroke","id":id,"page":2,"points":[Vector2(.1,.2),Vector2(.3,.4)],"color":"123456","width":3.0})
	game.electronics.save_notebook()
	var saved=store.read(game.characters.selected)
	assert(saved.page==2 and saved.strokes["2"].size()==1)
	assert(store.read("different-character").is_empty())
	game.school.papers.clear()
	game.school.request({"op":"notebook"})
	var restored=game.school.papers.values()[0]
	assert(restored.page==2 and restored.strokes==saved.strokes and restored.document_uid==legacy_uid)
	var legacy_id: int=restored.id
	game.school.request({"op":"stow","id":legacy_id})
	var purchase: String=game.electronics.profile.buy_study_tool("notebook")
	assert(game.electronics.profile.operation_succeeded,purchase)
	var supplies=preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
	var copies: Array=game.electronics.profile.data.dorm.carry_items.filter(func(item):return not supplies.notebook_uid(item).is_empty())
	assert(copies.size()==1)
	var key: String=copies[0]
	var uid: String=supplies.notebook_uid(key)
	game.electronics.open("notes",1)
	await game.electronics.open_notebook(key)
	var new_papers: Array=game.school.papers.values().filter(func(paper):return paper.get("document_uid","")==uid)
	assert(new_papers.size()==1 and new_papers[0].strokes.is_empty())
	var copy: Dictionary=new_papers[0]
	assert(game.paper_ui._reader_key(copy)!=game.paper_ui._reader_key(restored))
	game.school.request({"op":"stroke","id":copy.id,"page":0,"points":[Vector2(.2,.2),Vector2(.7,.4)],"color":"AA3322","width":8.0})
	game.electronics.save_notebook()
	var modern: Dictionary=store.read(game.characters.selected,uid)
	assert(modern.strokes["0"][0].color=="AA3322")
	assert(store.read(game.characters.selected).strokes==saved.strokes)
	game.paper_ui.close()
	game.school.papers.erase(copy.id)
	game.school.request({"op":key})
	new_papers=game.school.papers.values().filter(func(paper):return paper.get("document_uid","")==uid)
	assert(new_papers.size()==1 and new_papers[0].strokes==modern.strokes)
	var assignment := {"title":"Identical worksheet","questions":[]}
	var first: int=game.school._give(1,assignment,false,false)
	var second: int=game.school._give(1,assignment,false,false)
	assert(first!=0 and second!=0)
	assert(game.paper_ui._reader_key(game.school.papers[first])!=game.paper_ui._reader_key(game.school.papers[second]))
	game.school.papers[first].answers["temporary"]="first answer"
	assert(game.school.papers[second].answers.is_empty())
	print("INDEPENDENT_DOCUMENTS PASS")
	print("PASS: notebook manager opens paper, page and ink persist, character isolation, reopened notebook restores content")
	quit()
