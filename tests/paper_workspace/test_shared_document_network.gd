extends SceneTree
var game: Node
var role := ""
var expires := 0
const SPOT := Vector3(0,0.03,2)
func _initialize() -> void:call_deferred("run")
func wait_for(condition: Callable, label: String) -> bool:
	var until := Time.get_ticks_msec()+17000
	while Time.get_ticks_msec()<until:
		if condition.call():return true
		await create_timer(.07).timeout
	push_error("DOCUMENT_TEST "+role+" timeout "+label)
	quit(1)
	return false
func paper_id(tag: String) -> int:
	for item in game.school.papers.values():
		if item.project.get("title","")==tag:return int(item.id)
	return 0
func marks(id: int, page: String) -> int:
	return game.school.papers.get(id,{}).get("strokes",{}).get(page,[]).size()
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=2 or args[0] not in ["host","editor","observer"]:
		push_error("Use host, editor, or observer followed by the ENet port.")
		quit(1)
		return
	role=args[0]
	var port := int(args[1])
	game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for i in 5:await process_frame
	game.player.enabled=false
	if role=="host":
		assert(game.session.host_game("Document Owner",port)==OK)
		if not await wait_for(func():return game.session.roster.size()>=2,"join"):return
		game.campus_services._relocate(1,SPOT)
		for peer in game.session.roster:
			if int(peer)!=1:game.campus_services._relocate(peer,SPOT+Vector3(.9,0,0))
		if not game.school.identities.has(1):game.school._identify(1,game.school.local_identity)
		var id: int=game.school._give(1,{"title":"Fixture Notebook","questions":[],"guide_pages":[{"title":"Page 1","text":""},{"title":"Page 2","text":""}]},true,false,true)
		game.school.papers[id].merge({"notebook":true,"guide":true,"position":SPOT+Vector3(0,.80,.5),"held":false,"supply_released":true},true)
		var worksheet: int=game.school._give(1,{"title":"Fixture Worksheet","course_id":"ETY155","difficulty":1,"topic":0,"theory":"Ohm’s law","data":"12 V","procedure":"Calculate voltage.","source":"Fixture","questions":[{"prompt":"Voltage","unit":"V","options":[],"answer":"12"}]},true,false)
		game.school.papers[worksheet].held=false
		game.school.papers[worksheet].position=SPOT+Vector3(0,.8,-.5)
		game.school.broadcast()
		game.school.request({"op":"stroke","id":id,"page":0,"points":[Vector2(.2,.2),Vector2(.3,.3)]})
		if not await wait_for(func():return marks(id,"1")==1,"collaborator stroke"):return
		assert(game.school.papers[id].owner==1)
		for peer in game.session.roster:
			if int(peer)!=1:game.campus_services._relocate(peer,SPOT+Vector3(.9,0,0))
		if not await wait_for(func():return game.session.roster.size()>=3,"late observer"):return
		for peer in game.session.roster:
			if int(peer)!=1:game.campus_services._relocate(peer,SPOT+Vector3(.9,0,0))
		await create_timer(3.0).timeout
		var private: Dictionary= game.school.papers[id].duplicate(true)
		game.school.papers[id].stowed=true
		game.school.papers[id].revision+=1
		game.school.broadcast()
		assert(marks(id,"0")==1 and marks(id,"1")==1)
		assert(game.school.papers[id].document_uid==private.document_uid)
		if not await wait_for(func():return game.school.papers[worksheet].answers.get("0","")=="24","worksheet collaborator answer"):return
		assert(game.school.papers[worksheet].owner==1 and game.school.papers[worksheet].document_uid!=private.document_uid)
		game.school.papers[worksheet].mark={"reason":"Fixture graded"}
		game.school.papers[worksheet].revision+=1
		game.school.broadcast()
		await create_timer(2.0).timeout
		assert(game.school.papers[worksheet].answers["0"]=="24")
		assert(marks(id,"1")==1)
		game.school.request({"op":"pickup","id":worksheet})
		assert(game.school.papers[worksheet].held and game.school.papers[worksheet].answers["0"]=="24")
		game.school.request({"op":"stow","id":worksheet})
		game.school.request({"op":"equip_paper","id":worksheet})
		assert(game.school.papers[worksheet].held and game.school.papers[worksheet].answers["0"]=="24")
	else:
		if role=="observer":await create_timer(5.5).timeout
		assert(game.session.join_game("127.0.0.1",role,port)==OK)
		if not await wait_for(func():return paper_id("Fixture Notebook")!=0,"placed notebook"):return
		var id:=paper_id("Fixture Notebook")
		assert(marks(id,"0")==0)
		if not await wait_for(func():
			game.player.global_position=SPOT+Vector3(.85,0,0)
			game.session.send_pose({"position":game.player.global_position})
			game.school.request({"op":"open_document","id":id})
			return game.school.papers.get(id,{}).get("shared_access",false)
		,"open lease"):return
		if not await wait_for(func():return marks(id,"0")==1,"owner stroke"):return
		if role=="editor":
			var stroke := {"op":"stroke","id":id,"page":1,"points":[Vector2(.6,.5),Vector2(.68,.55)]}
			game.school.request(stroke)
			game.school._request.rpc_id(1,stroke)
			if not await wait_for(func():return marks(id,"1")==1,"own echo"):return
		else:
			if not await wait_for(func():return marks(id,"1")==1,"late snapshot"):return
		assert(game.school.papers[id].owner==1)
		if not await wait_for(func():return marks(id,"0")==0 and not game.school.papers.get(id,{}).get("shared_access",false),"stowed privacy"):return
		var sheet:=paper_id("Fixture Worksheet")
		assert(sheet!=0)
		if role=="editor":
			game.school.request({"op":"open_document","id":sheet})
			if not await wait_for(func():return game.school.papers[sheet].get("shared_access",false),"open worksheet"):return
			assert(not game.school.papers[sheet].project.questions[0].has("answer"))
			game.school.request({"op":"answer","id":sheet,"key":"0","value":"24"})
			if not await wait_for(func():return not game.school.papers[sheet].get("shared_capable",true),"marked worksheet lock"):return
			game.school.request({"op":"answer","id":sheet,"key":"0","value":"99"})
		assert(game.school.papers[sheet].owner==1)
	print("SHARED_DOCUMENT_RUNTIME PASS ",role)
	quit(0)
