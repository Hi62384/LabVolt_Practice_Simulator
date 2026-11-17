extends Node3D
## Local room display driven only by the recipient-safe host snapshot.
const TeachingBoard=preload("res://scripts/campus/academics/teaching_board.gd")
const Layout=preload("res://scripts/campus/academics/classroom_layout.gd")
var game: Node
var board: Node3D
var active_room: String=""

func configure(owner: Node) -> void:
 game=owner
 board=TeachingBoard.new();board.event_mode=true;add_child(board);board.set_room_active(false)

func apply(room: String,snapshot: Dictionary) -> void:
 if not is_instance_valid(board):return
 if snapshot.is_empty() or snapshot.get("mode","") not in ["quiz","demonstration","mistake","teacher","mystery","duel","pass","race"]:
  board.set_room_active(false);active_room="";return
 if not is_instance_valid(game) or game.get("campus")==null:return
 var data: Dictionary=game.campus.registry.get_room(room)
 if data.is_empty():return
 if active_room!=room:
  active_room=room
  var center:=Layout.point(data.get("center",data.get("anchor",Vector3.ZERO)))
  # Sit just in front of the ordinary teaching board to avoid coplanar depth flicker.
  board.global_position=center+Vector3(0,2.18,-5.65)
  board.rotation.y=0.0
 board.set_room_active(true)
 var question: Dictionary=snapshot.get("question",{})
 var closed:=bool(snapshot.get("closed",snapshot.has("reveal")))
 var prompt: String=str(question.get("prompt","Class question")).left(600)
 if snapshot.get("mode","")=="demonstration" and not str(question.get("summary","")).is_empty():prompt=str(question.summary).left(160)
 var lines: Array[String]=[prompt]
 var choices: Variant=question.get("options",[])
 if not closed and choices is Array:
  for i in mini(choices.size(),6):lines.append("%d. %s"%[i+1,str(choices[i]).left(110)])
 if snapshot.get("mode","")=="board":
  for entry in snapshot.get("shared",{}).get("entries",[]):lines.append("• "+str(entry.get("text","")).left(160))
 for clue in snapshot.get("clues",[]):lines.append(str(clue).left(160))
 if not closed and snapshot.get("hands",{}).get("called",false):lines.append("The teacher has called on a student")
 if closed:
  var reveal: Dictionary=snapshot.get("reveal",{})
  if reveal.has("answer"):lines.append("Answer: "+str(reveal.answer).left(200))
  if snapshot.get("mode","")=="teacher":lines.append("%d students solved it before the teacher"%int(snapshot.get("teacher_result",{}).get("students_beat_teacher",0)))
  if snapshot.get("mode","")=="duel":lines.append("Winner: "+str(snapshot.get("duel",{}).get("winner","No correct answer")))
  if snapshot.get("mode","")=="race":lines.append("Fastest correct: "+str(snapshot.get("race",{}).get("winner","No correct answer")))
  if snapshot.has("teacher_comment") and not reveal.has("diagram"):lines.append("Teacher: "+str(snapshot.teacher_comment).left(160))
  if snapshot.get("mode","")=="pass":
   for step in snapshot.get("reveal",{}).get("steps",[]):lines.append("Step %d · %s"%[int(step.get("step",0)),"correct" if step.get("correct",false) else "review"])
  if snapshot.get("mode","") in ["demonstration","mistake","mystery"] and reveal.has("initial_ma"):lines.append("Simulated: %.2f mA → %.2f mA · %s"%[float(reveal.get("initial_ma",0.0)),float(reveal.get("changed_ma",0.0)),str(reveal.get("source",""))])
  if reveal.has("explanation"):lines.append(str(reveal.explanation).left(180))
  var leaders: Array=snapshot.get("leaderboard",[])
  if not leaders.is_empty():
   lines.append("Round leaders")
   for leader in leaders:lines.append("%s · %d"%[str(leader.get("name","Student")).left(30),int(leader.get("points",0))])
 var status: String="Starting · %d s"%ceili(float(snapshot.get("seconds_left",0.0))) if snapshot.get("stage","")=="announcing" else ("Results" if closed else "%d s remaining"%ceili(float(snapshot.get("seconds_left",0.0))))
 var mode: String=str(snapshot.get("mode","quiz"))
 var heading: String="Class quiz" if mode=="quiz" else ("Teacher demonstration" if mode=="demonstration" else ("Find the mistake" if mode=="mistake" else ("Beat the teacher" if mode=="teacher" else ("Classroom mystery" if mode=="mystery" else ("Student challenge" if mode=="duel" else ("Pass the problem" if mode=="pass" else ("Fastest answer" if mode=="race" else "Shared board")))))))
 var stage_title: String="Round %d of %d"%[int(snapshot.get("round_number",1)),int(snapshot.get("rounds_total",1))] if mode=="quiz" else heading
 var stage: Dictionary={"title":stage_title,"text":"\n".join(lines)}
 if closed and snapshot.get("reveal",{}).get("diagram",{}) is Dictionary:stage.diagram=snapshot.get("reveal",{}).get("diagram",{})
 board.show_content(str(snapshot.get("course","")),"lesson",heading,stage,status)

func clear() -> void:
 if is_instance_valid(board):board.set_room_active(false)
 active_room=""
