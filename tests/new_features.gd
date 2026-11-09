extends SceneTree
const Toon=preload("res://scripts/toon_character.gd")
const Calc=preload("res://scripts/scientific_calculator.gd")
var failures:=0
var count:=0
func check(value: bool,label: String):
 count+=1
 if not value:failures+=1;printerr("FAIL NEW: "+label)
func _initialize():call_deferred("run")
func run():
 for entry in [["1/2",true,.5],["sin(30)",true,.5],["cos(60)+2^3",true,8.5],["atan(1)",true,45.],["sin(pi/2)",false,1.],["log(100)",true,2.],["ln(exp(2))",true,2.],["sqrt(3)*208*.5",true,180.133283987]]:
  var result=Calc.calculate(entry[0],entry[1]);check(result.ok and abs(result.get("value",-999)-entry[2])<.00001,"calculator "+entry[0])
 check(not Calc.calculate("OS.execute(1)").ok,"calculator rejects object access")
 check(Calc.calculate("sin(30").ok and abs(float(Calc.calculate("sin(30").value)-.5)<.00001,"calculator closes omitted trailing parentheses")
 for i in 6:
  var path="user://toon_%d.glb"%i
  check(Toon.save_glb(Toon.preset(i),path)==OK,"preset export "+str(i))
  var bytes=FileAccess.get_file_as_bytes(path)
  check(preload("res://scripts/avatar_model.gd").valid(bytes),"portable preset "+str(i))
  var model=preload("res://scripts/avatar_model.gd").build(bytes)
  check(model!=null and not model.find_children("*","AnimationPlayer",true,false).is_empty(),"animated preset "+str(i));model.free()
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game);await create_timer(.3).timeout
 var previous_profiles: int=game.characters.profiles.size()
 game.characters.edit(true)
 check(game.characters.is_editing() and game.characters.editor_studio.get_window()==root,"creator lives in game window")
 var editor=game.characters.editor_studio
 for category in ["Body","Face","Hair","Outfit","Looks"]:editor.category=category;editor._options()
 editor._set_value("hair","Bun");editor._undo();check(editor.config.hair=="Sweep","undo restores appearance")
 editor._redo();check(editor.config.hair=="Bun","redo restores change")
 editor.config.name="Cartoon test";editor.name_edit.text="Cartoon test";await editor._save()
 check(not game.characters.is_editing() and game.characters.profiles.size()==previous_profiles+1,"save returns and selects profile")
 var id=game.characters.selected;game.characters.edit(false)
 check(game.characters.editor_studio.config.hair=="Bun","edit reloads saved settings")
 game.characters._editor_closed(false);check(game.characters.selected==id,"cancel preserves selected profile")
 for n in 3:
  var lab=game.session.labs[n];lab.cables.clear();lab.powered=false
  for i in 2:
   lab.cables.append({"id":lab.next_id,"a":"TX_1","b":"","owner":1,"creator":1,"color":i});lab.next_id+=1
   check(lab.act(1,{"op":"plug","port":"TX_2"},lab.positions.TX_2)=="","parallel lead at station "+str(n))
  lab.cables.append({"id":lab.next_id,"a":"TX_1","b":"","owner":1,"creator":1,"color":2});lab.next_id+=1
  check(lab.act(1,{"op":"plug","port":"TX_1"},lab.positions.TX_1)=="","same-terminal loop at station "+str(n))
  lab.cables.clear()
  check(lab.act(1,{"op":"power"},lab.positions.power)=="" and lab.powered,"power on at station "+str(n))
  for i in 25:lab.act(1,{"op":"voltage","delta":-.05},lab.positions.variable)
  check(lab.level==0,"live voltage reaches zero")
  for i in 25:lab.act(1,{"op":"voltage","delta":.05},lab.positions.variable)
  check(lab.level==1,"live voltage reaches 100 percent")
  lab.act(1,{"op":"supply_meter"},lab.positions.supply_meter);check(lab.supply_meter==2,"voltmeter selector")
  lab.act(1,{"op":"dyn_load","delta":.1},lab.positions.dyn_load);check(lab.dyn_load==.1,"dynamometer load")
  lab.act(1,{"op":"dyn_measure","pressed":true},lab.positions.dyn_measure);check(lab.dyn_measure,"measurement hold")
  lab.act(1,{"op":"dyn_measure","pressed":false},lab.positions.dyn_measure);check(not lab.dyn_measure,"measurement release")
  lab.act(1,{"op":"power"},lab.positions.power)
  lab.act(1,{"op":"switch","kind":"R","index":0,"expected":false},lab.positions.R_0)
 game._receive_state(game.session.world_snapshot())
 for n in 2:check(game.stations[n].equipment.switch_meshes.R_0.indicator.material_override.emission_enabled,"side bench green indicator "+str(n))
 game.school.start("Freeplay",0);game.session.poses[1].position=game.school.teacher_position
 game.school.request({"op":"new","topic":2,"difficulty":0,"lesson":true})
 var paper_id=game.school.held(1);var paper=game.school.papers[paper_id]
 check(paper.project.questions.size()==3,"lesson has fewer practice questions")
 var before=game.school.average()
 for i in paper.project.questions.size():game.school.request({"op":"answer","id":paper_id,"key":str(i),"value":str(paper.project.questions[i].answer)})
 game.school.request({"op":"stroke","id":paper_id,"page":2,"points":[Vector2(.1,.1),Vector2(.2,.2)],"color":"b24c45","width":5.})
 check(paper.strokes['2'][0].color=="b24c45" and paper.strokes['2'][0].width==5.,"colored pencil data retained")
 game.school.request({"op":"lesson_check","id":paper_id})
 check(paper.mark.score==100 and game.school.average()==before,"practice marked without affecting average")
 game.paper_ui.open_sheet(paper_id);game.paper_ui.turn_page(3)
 await create_timer(.2).timeout
 check(game.paper_ui.page_view!=null and game.paper_ui.calculator_widget!=null,"paper and calculator reader")
 game.school.request({"op":"lesson_retry","id":paper_id});check(paper.mark.is_empty(),"lesson can be retried")
 game.queue_free();await process_frame;await process_frame
 print("NEW FEATURES: %d checks, %d failures"%[count,failures]);quit(1 if failures else 0)
