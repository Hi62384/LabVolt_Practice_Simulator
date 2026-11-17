extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await physics_frame
 var room: Dictionary=game.campus.registry.get_room("study")
 assert(room.get("size",[]).size()==3 and float(room["size"][0])==10.0 and float(room["size"][2])==8.0)
 assert(game.campus.registry.locate(Vector3(5,5.1,33))=="study")
 game.school._ensure_classroom_whiteboards()
 var board: Dictionary={}
 for paper in game.school.papers.values():
  if paper.get("classroom_board","")=="study":board=paper
 assert(not board.is_empty() and board.board_size.x>=5.0)
 assert(game.campus.registry.locate(board.position)=="study")
 var study=game.campus.get_node("QuietStudy")
 var tables:=0;var chairs:=0
 for item in study.get_children():
  if item.get_meta("role","")=="table":tables+=1
  if item.get_meta("role","")=="facility_seat":chairs+=1
 assert(tables==2)
 var rolling:=0
 for chair in game.chairs:
  if chair.name.begins_with("StudyRollingChair_"):rolling+=1
 assert(rolling==8)
 print("PASS compact study room, whiteboard and two tables")
 quit()
