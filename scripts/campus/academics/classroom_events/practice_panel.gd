extends PanelContainer
## Practice input; owner controls network and focus.
signal submitted(response: Variant)
signal dismissed
signal hand_changed(raised: bool)
signal contributed(value: String)
signal explained(value: String)
signal vote_requested(agree: bool)
signal hint_requested
signal declined
var options: OptionButton
var entry: LineEdit
var submit_button: Button
var math_view: Control
var status_label: Label
var timer_label: Label
var seconds_left:=0.0
var hand_button: Button
var hint_button: Button
var decline_button: Button
var hint_label: Label
var hand_label: Label
var title_label: Label
var submission_pending:=false
var submission_accepted:=false
var contribution_entry: LineEdit
var contribution_button: Button
var explanation_entry: LineEdit
var explanation_button: Button
var shared_notes: Label
var shared_scroll: ScrollContainer
var vote_label: Label
var agree_button: Button
var disagree_button: Button
var clue_label: Label
var prompt_label: Label
var displayed_step:=-1

func build(question: Dictionary,course: String="") -> bool:
 var choices: Variant=question.get("options",[])
 if not preload("res://scripts/campus/academics/classroom_events/practice_round.gd").supports_question(question,course):return false
 theme=preload("res://scripts/ui/design_system/theme.gd").create()
 add_theme_stylebox_override("panel",preload("res://scripts/ui/design_system/theme.gd").card_style())
 custom_minimum_size.x=0
 var column:=VBoxContainer.new();column.add_theme_constant_override("separation",8);add_child(column)
 title_label=Label.new();title_label.text="Practice question";column.add_child(title_label)
 timer_label=Label.new();column.add_child(timer_label)
 clue_label=Label.new();clue_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(clue_label);clue_label.hide()
 prompt_label=Label.new();prompt_label.text=str(question.get("prompt",""));prompt_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(prompt_label)
 if course in ["MTH147","MTH255"] and str(question.get("input",{}).get("kind",""))!="choice":
  math_view=preload("res://scripts/mth255/worksheet_adapter.gd").new() if course=="MTH255" else preload("res://scripts/math_ui/workspace.gd").new()
  var scroll:=ScrollContainer.new();scroll.custom_minimum_size=Vector2(340,220)
  scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
  scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
  column.add_child(scroll);scroll.add_child(math_view)
  math_view.configure(question,true,{"formula_allowed":false})
 elif not choices.is_empty():
  options=OptionButton.new()
  for item in choices:options.add_item(str(item).left(160))
  options.select(-1);column.add_child(options)
 else:
  entry=LineEdit.new();entry.max_length=256;entry.placeholder_text="Your answer";entry.text_submitted.connect(func(_value: String): _submit());column.add_child(entry)
 var row:=HFlowContainer.new();column.add_child(row)
 submit_button=Button.new();submit_button.text="Submit";submit_button.pressed.connect(_submit);row.add_child(submit_button)
 hand_button=Button.new();hand_button.toggle_mode=true;hand_button.text="Raise hand";hand_button.toggled.connect(func(raised: bool):hand_changed.emit(raised));row.add_child(hand_button)
 hint_button=Button.new();hint_button.text="Hint";hint_button.pressed.connect(func():hint_requested.emit());row.add_child(hint_button)
 decline_button=Button.new();decline_button.text="Skip practice";decline_button.pressed.connect(func():declined.emit());row.add_child(decline_button)
 hint_label=Label.new();hint_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;hint_label.hide();column.add_child(hint_label)
 vote_label=Label.new();vote_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(vote_label);vote_label.hide()
 var vote_row:=HBoxContainer.new();column.add_child(vote_row)
 agree_button=Button.new();agree_button.text="Agree";agree_button.pressed.connect(func():vote_requested.emit(true));vote_row.add_child(agree_button);agree_button.hide()
 disagree_button=Button.new();disagree_button.text="Needs revision";disagree_button.pressed.connect(func():vote_requested.emit(false));vote_row.add_child(disagree_button);disagree_button.hide()
 contribution_entry=LineEdit.new();contribution_entry.max_length=160;contribution_entry.placeholder_text="Board or group note";column.add_child(contribution_entry)
 contribution_entry.hide()
 contribution_button=Button.new();contribution_button.text="Add note";contribution_button.pressed.connect(func():
  var value:=contribution_entry.text.strip_edges()
  if not value.is_empty():contributed.emit(value)
 );column.add_child(contribution_button);contribution_button.hide()
 explanation_entry=LineEdit.new();explanation_entry.max_length=160;explanation_entry.placeholder_text="Explain a teammate's note or suggest a check";column.add_child(explanation_entry);explanation_entry.hide()
 explanation_button=Button.new();explanation_button.text="Help teammate";explanation_button.pressed.connect(func():
  var value:=explanation_entry.text.strip_edges()
  if not value.is_empty():explained.emit(value)
 );column.add_child(explanation_button);explanation_button.hide()
 shared_scroll=ScrollContainer.new();shared_scroll.custom_minimum_size=Vector2(340,84);column.add_child(shared_scroll);shared_scroll.hide()
 shared_notes=Label.new();shared_notes.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;shared_notes.custom_minimum_size.x=320;shared_scroll.add_child(shared_notes)
 var close:=Button.new();close.text="Close";close.pressed.connect(func():dismissed.emit());row.add_child(close)
 status_label=Label.new();status_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(status_label)
 hand_label=Label.new();column.add_child(hand_label)
 return true

func update_state(state: Dictionary) -> void:
 if is_instance_valid(title_label):title_label.text="Timed class quiz" if state.get("mode","")=="quiz" else "Practice question"
 if is_instance_valid(title_label) and state.get("mode","")=="quiz":title_label.text="Class quiz · Round %d of %d"%[int(state.get("round_number",1)),int(state.get("rounds_total",1))]
 if is_instance_valid(title_label) and state.get("mode","") in ["board","group"]:title_label.text="Shared board" if state.mode=="board" else "Group exercise"
 if is_instance_valid(title_label) and state.get("mode","")=="demonstration":title_label.text="Predict the result"
 if is_instance_valid(title_label) and state.get("mode","")=="mistake":title_label.text="Find the mistake"
 if is_instance_valid(title_label) and state.get("mode","")=="teacher":title_label.text="Beat the teacher"
 if is_instance_valid(title_label) and state.get("mode","")=="mystery":title_label.text="Classroom mystery"
 if is_instance_valid(title_label) and state.get("mode","")=="duel":title_label.text="Student challenge"
 if is_instance_valid(title_label) and state.get("mode","")=="pass":title_label.text="Pass the problem · Step %d of %d"%[mini(3,int(state.get("pass_step",0))+1),int(state.get("pass_total",3))]
 if is_instance_valid(title_label) and state.get("mode","")=="race":title_label.text="Fastest answer"
 if is_instance_valid(title_label) and state.get("mode","")=="physical":title_label.text="Live AC station observation"
 if state.get("mode","")=="pass":
  if is_instance_valid(prompt_label):prompt_label.text=str(state.get("question",{}).get("prompt","")).left(500)
  if displayed_step!=int(state.get("pass_step",0)):
   displayed_step=int(state.get("pass_step",0));submission_pending=false;submission_accepted=false
   if is_instance_valid(entry):entry.clear()
 var shared: Dictionary=state.get("shared",{})
 if is_instance_valid(prompt_label) and state.get("mode","")=="group" and not str(shared.get("task","")).is_empty():prompt_label.text="Team %s: %s\n\n%s"%[str(shared.get("group","A")),str(shared.task).left(160),str(state.get("question",{}).get("prompt","")).left(500)]
 if is_instance_valid(clue_label):
  clue_label.visible=not state.get("clues",[]).is_empty()
  clue_label.text="\n".join(state.get("clues",[]))
 var board_writer: bool=state.get("mode","")!="board" or bool(state.get("hands",{}).get("selected",false))
 if is_instance_valid(contribution_entry):contribution_entry.visible=not shared.is_empty() and board_writer
 if is_instance_valid(contribution_button):
  contribution_button.visible=not shared.is_empty() and board_writer
  contribution_button.disabled=not bool(shared.get("can_contribute",false)) or bool(state.get("closed",false)) or str(shared.get("group","")).is_empty()
  contribution_button.text="Added to board" if shared.get("contributed",false) else "Add note"
 if is_instance_valid(shared_notes):
  shared_scroll.visible=not shared.is_empty() and not shared.get("entries",[]).is_empty()
  var notes: Array[String]=[]
  for note in shared.get("entries",[]):
   var author: String=note.get("name","")
   if author.is_empty():author="Teammate explanation" if note.get("kind","")=="explanation" else "Note"
   notes.append("• %s: %s"%[author,note.get("text","")])
  shared_notes.text="\n".join(notes)
 var can_vote: bool=state.get("mode","")=="group" and not str(shared.get("proposal","")).is_empty() and not str(shared.get("group","")).is_empty()
 if is_instance_valid(vote_label):
  vote_label.visible=can_vote
  if can_vote:vote_label.text="Team proposal: %s\nAgree %d · Needs revision %d"%[str(shared.proposal).left(120),int(shared.get("agree",0)),int(shared.get("disagree",0))]
 if is_instance_valid(agree_button):
  agree_button.visible=can_vote;agree_button.disabled=state.get("closed",false) or shared.get("vote") is bool and bool(shared.vote)
 if is_instance_valid(disagree_button):
  disagree_button.visible=can_vote;disagree_button.disabled=state.get("closed",false) or shared.get("vote") is bool and not bool(shared.vote)
 if is_instance_valid(contribution_entry) and shared.get("contributed",false):contribution_entry.editable=false
 var can_explain:=bool(shared.get("can_explain",false)) and not bool(state.get("closed",false))
 if is_instance_valid(explanation_entry):explanation_entry.visible=state.get("mode","")=="group" and not shared.is_empty();explanation_entry.editable=can_explain
 if is_instance_valid(explanation_button):explanation_button.visible=state.get("mode","")=="group" and not shared.is_empty();explanation_button.disabled=not can_explain;explanation_button.text="Helped teammate" if shared.get("explained",false) else "Help teammate"
 if is_instance_valid(hint_button):
  hint_button.visible=state.get("mode","") in ["practice","board","group","teacher"]
  hint_button.disabled=not bool(state.get("can_hint",false))
 if is_instance_valid(decline_button):
  decline_button.visible=state.get("mode","")=="practice"
  decline_button.disabled=not bool(state.get("can_submit",false)) or bool(state.get("declined",false))
 if is_instance_valid(hint_label):
  hint_label.visible=state.has("hint")
  hint_label.text="Teacher hint · "+str(state.get("hint","")).left(220)
 seconds_left=maxf(0.0,float(state.get("seconds_left",0.0)))
 if state.get("submitted",false):submission_accepted=true;submission_pending=false
 if state.has("result"):submission_pending=false
 if is_instance_valid(submit_button):submit_button.disabled=submission_pending or submission_accepted or not bool(state.get("can_submit",false))
 if is_instance_valid(hand_button):
  var hands: Dictionary=state.get("hands",{})
  hand_button.set_pressed_no_signal(bool(hands.get("raised",false)))
  hand_button.text="Lower hand" if hand_button.button_pressed else "Raise hand"
  var duel: Dictionary=state.get("duel",{})
  if not duel.is_empty():hand_button.text="Withdraw" if hand_button.button_pressed else "Volunteer"
  hand_button.disabled=state.has("result") or (bool(duel.get("locked",false)) if not duel.is_empty() else (not state.get("can_submit",false) and not state.get("submitted",false)))
  if is_instance_valid(hand_label):hand_label.text="The teacher called on you." if hands.get("selected",false) else ("The teacher called on a student." if hands.get("called",false) else ("Hand raised." if hands.get("raised",false) else ""))
  if is_instance_valid(hand_label) and not duel.is_empty():hand_label.text="Your turn to solve." if duel.get("selected",false) else ("%d student(s) competing."%int(duel.get("competitors",0)) if duel.get("locked",false) else "Volunteer to compete. The round begins in a few seconds.")
  if is_instance_valid(hand_label) and state.get("mode","")=="board" and hands.get("selected",false):hand_label.text="Your turn: walk to the whiteboard. Put down held items, then use the class marker."
  if is_instance_valid(hand_label) and state.get("mode","")=="board" and state.get("submitted",false):hand_label.text="Solution submitted. Return to your seat."
 if not is_instance_valid(status_label):return
 if state.get("declined",false):status_label.text="You skipped this optional practice. The class continues; no grade is recorded."
 elif state.has("result"):
  var result: Dictionary=state.result
  if result.is_empty():status_label.text="Quiz closed. No answer submitted." if state.get("mode","")=="quiz" else "Practice closed. No answer submitted."
  else:
   status_label.text=("Correct. " if result.get("correct",false) else "Review your answer. ")+str(result.get("reason",result.get("explanation",""))).left(400)
   if state.get("mode","")=="quiz":status_label.text+="  Score: %d points."%int(result.get("points",0))
  if state.has("totals"):status_label.text+="  Class: %d correct of %d answers · %d total points."%[int(state.totals.correct),int(state.totals.answered),int(state.totals.get("total_points",0))]
  if state.get("mode","")=="quiz":
   status_label.text+="  Your total: %d · Streak: %d."%[int(state.get("personal_points",0)),int(state.get("streak",0))]
   var leaders: Array=state.get("leaderboard",[])
   if not leaders.is_empty():
    status_label.text+="  Leaders: "
    for leader in leaders:status_label.text+="%s %d  "%[str(leader.get("name","Student")),int(leader.get("points",0))]
   var teams: Dictionary=state.get("team_scores",{})
   if not teams.is_empty():status_label.text+="  Teams A %d · B %d."%[int(teams.get("A",0)),int(teams.get("B",0))]
  if state.get("mode","")=="duel":status_label.text+="  Winner: %s."%str(state.get("duel",{}).get("winner",""))
  if state.get("mode","")=="race":status_label.text+="  Winner: %s."%str(state.get("race",{}).get("winner",""))
  if state.get("mode","")=="physical":
   var measurement: Dictionary=state.get("reveal",{})
   if measurement.has("after_v"):status_label.text+="  Station %d, voltmeter %d: %.2f V → %.2f V RMS."%[int(state.get("station",0)),int(measurement.channel),float(measurement.before_v),float(measurement.after_v)]
   elif measurement.has("fault"):status_label.text+="  Station fault: "+str(measurement.fault).left(160)
   elif measurement.has("status"):status_label.text+="  "+str(measurement.status).left(160)
  if state.has("teacher_comment"):status_label.text+="  Result: "+str(state.teacher_comment).left(160)
 elif state.get("submitted",false):status_label.text="Answer submitted. Feedback appears when practice ends."
 elif state.has("progress"):
  var progress: Dictionary=state.progress
  status_label.text="Result: "+str(progress.get("message","Review your answer.")).left(180)+" %d attempt remaining."%int(progress.get("attempts_left",0))
 elif state.get("mode","")=="pass":status_label.text="Your step." if state.get("pass_turn",false) else "Waiting for the next student."
 elif state.get("mode","")=="physical":status_label.text="Station changed; the host will show the measured result at the end." if state.get("measurement_changed",false) else ("Station tripped; reset it safely before time runs out." if state.get("equipment_fault",false) else "Use the station controls to make a measurement change.")
 elif not shared.is_empty():status_label.text="Group %s · %d notes"%[str(shared.get("group","A")),int(shared.get("count",0))]
 if state.get("mode","")=="group" and state.has("team_progress"):
  var team_progress: Dictionary=state.team_progress
  status_label.text+="\nTeam %s · %d present · %d notes · %d explanations · %d submitted"%[str(shared.get("group","A")),int(team_progress.members),int(team_progress.notes),int(team_progress.explanations),int(team_progress.submitted)]
 if state.get("mode","")=="group" and not str(state.get("team_prompt","")).is_empty():status_label.text+="\nTeacher to your team: "+str(state.team_prompt).left(180)
 if state.get("mode","")=="group" and state.has("group_result"):
  var group_result: Dictionary=state.group_result
  status_label.text+="  Group %s: %d correct of %d answers (%d members)."%[str(group_result.team),int(group_result.correct),int(group_result.answered),int(group_result.members)]
  if group_result.has("fastest_team"):status_label.text+="  Team %s had the fastest correct submission (%.1f s)."%[str(group_result.fastest_team),float(group_result.fastest_seconds)]
 if state.has("class_notice"):status_label.text+="\n"+str(state.class_notice).left(120)

func action_status(op: String,status: String) -> void:
 if not is_instance_valid(status_label):return
 if op=="submit":submission_pending=false
 if op=="submit" and status=="accepted":submission_accepted=true
 if op=="submit" and status=="retry":
  status_label.text="Check your answer and try once more."
  if is_instance_valid(submit_button) and seconds_left>0.0:submit_button.disabled=false
  return
 if status=="accepted" and op=="submit":status_label.text="Answer submitted. Feedback appears when practice ends."
 elif status=="accepted" and op=="hint":return
 elif status=="accepted":return
 else:
  var prefix: String="Answer not submitted: " if op=="submit" else ("Hint unavailable: " if op=="hint" else ("Group vote failed: " if op=="vote" else "Class action failed: "))
  status_label.text=prefix+status.replace("_"," ")+"."
  if op=="submit" and is_instance_valid(submit_button) and seconds_left>0.0:submit_button.disabled=false

func _process(delta: float) -> void:
 if not is_instance_valid(timer_label):return
 seconds_left=maxf(0.0,seconds_left-delta)
 timer_label.text="Time remaining: %d s"%ceili(seconds_left)

func _submit() -> void:
 if submission_pending or submit_button.disabled:return
 var response: Variant
 if is_instance_valid(math_view):
  response=math_view.answer()
 elif is_instance_valid(options):
  if options.selected<0:return
  response=str(options.selected)
 elif is_instance_valid(entry):
  response=entry.text.strip_edges()
  if response.is_empty():return
 else:return
 submission_pending=true;submit_button.disabled=true;submitted.emit(response)
