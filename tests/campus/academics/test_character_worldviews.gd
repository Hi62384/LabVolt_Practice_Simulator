extends SceneTree
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")
const Behavior=preload("res://scripts/campus/academics/character_behavior.gd")
const Affect=preload("res://scripts/campus/academics/character_affect.gd")
const Motion=preload("res://scripts/campus/academics/character_motion.gd")
const Knowledge=preload("res://scripts/campus/academics/character_knowledge.gd")
const Toon=preload("res://scripts/toon_character.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var worldviews:={}
	for id in Roster.PEOPLE:
		var person:=Profiles.teacher(id)
		assert(person.beliefs.size()>=5,id)
		assert(person.behavior_examples.size()>=3,id)
		worldviews[person.worldview]=true
		assert(person.traits.values().all(func(value):return is_finite(float(value)) and float(value)>=0. and float(value)<=1.),id)
		assert(Behavior.personality_instructions(person).contains(person.worldview),id)
		assert(not Behavior.personality_instructions(person).contains("300 characters"),id)
	assert(worldviews.size()==Roster.PEOPLE.size())
	var chad:=Profiles.teacher("chad")
	var bird:=Profiles.teacher("ms_bird_heart")
	var brian:=Profiles.teacher("brian")
	var stone:=Profiles.teacher("mr_stone")
	var bro:=Profiles.teacher("mr_bro")
	var stanley:=Profiles.teacher("stanley")
	for question in ["I'm excited to be here.","I love college.","Should I drop out?","I don't care about becoming rich."]:
		var decision:=Behavior.priorities(chad,question,{},"lesson")
		assert(decision.goal=="challenge_ambition",question)
		assert(not Behavior.fallback(chad,decision,question,"").is_empty(),question)
	assert(Behavior.priorities(chad,"How do you escape the matrix?",{},"lesson").goal=="pursue_interest")
	var revised_chad:=chad.duplicate(true)
	var revised_education:="A practical college program can build independence when it opens work you choose for yourself."
	revised_chad.beliefs[0].authored_position=revised_chad.beliefs[0].position
	revised_chad.beliefs[0].position=revised_education
	revised_chad.beliefs[0].history_count=9
	for question in ["I'm excited to be here.","Should I leave college?","How do you escape the matrix?"]:
		var decision:=Behavior.priorities(revised_chad,question,{},"lesson")
		assert(Behavior.fallback(revised_chad,decision,question,"")==revised_education,"Offline speech must preserve the saved current opinion: "+question)
	assert(Behavior.fallback(revised_chad,{"strategy":"defend_belief"},"Your opinion about college is wrong.","")==revised_education)
	assert(Behavior.fallback(revised_chad,{"strategy":"protect_assessment","phase":"assignment"},"What is the answer?","")!=revised_education,"A saved opinion does not bypass assessment priorities")
	assert(Behavior.fallback(revised_chad,{"strategy":"confront"},"You're an idiot.","")!=revised_education,"An insult does not force an unrelated statement of the revised opinion")
	revised_chad.beliefs[0].position=revised_chad.beliefs[0].authored_position
	assert(Behavior.fallback(revised_chad,Behavior.priorities(revised_chad,"I love college.",{},"lesson"),"I love college.","")!=revised_education,"A conviction-only update preserves the authored position")
	assert(Behavior.priorities(chad,"Can you explain this equation?",{},"lesson").goal=="give_minimum")
	assert(Behavior.priorities(bird,"Can you explain this equation?",{},"lesson").goal=="coach")
	assert(Behavior.priorities(Profiles.teacher("jeff"),"How's your project?",{},"freeplay").goal=="share_personal_project")
	var emotions:={"anger":.8,"irritation":.9,"sadness":.6}
	var strategies:={}
	for person in [chad,bird,brian,stone,bro,stanley]:
		var seen:={}
		for turn in 9:
			var choice:=Behavior.reaction(person,"insult",{"resentment":turn},emotions,"lesson",turn)
			choice.repetition=turn
			strategies[choice.strategy]=true
			if not choice.quiet:
				var line:=Behavior.fallback(person,choice,"I've met rocks that teach better than you.","")
				assert(not line.is_empty(),str(person.id)+":"+str(choice))
				seen[line]=true
			if person.id in ["chad","brian"]:assert(not choice.closed,person.id)
		if person.id!="stanley":assert(seen.size()>=3,str(person.id)+":"+str(seen))
	assert(strategies.size()>=9,str(strategies))
	assert(Behavior.reaction(stone,"insult",{},emotions,"lesson",6).strategy=="request_discipline")
	assert(Behavior.reaction(bird,"insult",{},emotions,"lesson",8).quiet)
	assert(Behavior.reaction(stanley,"insult",{},emotions,"lesson",0).quiet)
	var calm:={"anger":0.,"irritation":.1}
	assert(not Behavior.action_willingness(chad,"approach",{},"lesson",{"goal":"give_minimum"},calm).accepted)
	assert(Behavior.action_willingness(chad,"nod",{},"lesson",{"goal":"give_minimum"},calm).accepted)
	assert(Behavior.action_willingness(bird,"approach",{},"lesson",{"goal":"coach"},calm).accepted)
	assert(not Behavior.action_willingness(bird,"approach",{},"lesson",{"closed":true,"strategy":"withdraw_hurt"},calm).accepted)
	assert(not Behavior.action_willingness(bro,"approach",{},"assignment",{},calm).accepted)
	assert(Behavior.action_willingness(bro,"nod",{},"assignment",{},calm).accepted)
	assert(Behavior.action_willingness(chad,"approach",{"dimensions":{"respect":.95,"friendship":.5}},"freeplay",{"goal":"pursue_interest"},calm).accepted)
	assert(not Behavior.action_willingness(brian,"approach",{"dimensions":{"resentment":.9,"respect":.1}},"lesson",{},emotions).accepted)
	assert(Behavior.action_willingness(stanley,"approach",{},"assignment",{"goal":"protect_safety"},emotions).accepted)
	assert(not Behavior.action_willingness(bird,"grant_grade",{},"freeplay",{},calm).accepted)
	var values:=Affect.baseline(brian.traits)
	Affect.apply(values,brian.traits,"insult",1.)
	var anger:float=values.anger
	Affect.recover(values,brian.traits,20.)
	assert(float(values.anger)>anger*.85,"Meaningful anger must survive a 20-second pause")
	Affect.apply(values,brian.traits,"apology",1.)
	assert(float(values.anger)>.25,"One apology must not erase Brian's anger")
	var original:=values.duplicate(true)
	Affect.apply(values,brian.traits,"disagreement",1.)
	assert(float(values.interest)>float(original.interest))
	var unknown:=Knowledge.assess(stanley,{},"Explain the technique.",{"domain":"specialist_unknown","difficulty":.95})
	assert(not unknown.allowed)
	assert(Knowledge.assess(Profiles.teacher("dr_volts"),{},"Explain resonance.",{"domain":"physics","difficulty":.6}).allowed)
	assert(Knowledge.assess(Profiles.teacher("bill_nye"),{},"Explain the experiment.",{"domain":"science","difficulty":.6}).allowed)
	assert(not Knowledge.assess(stanley,{},"What is the latest price?",{"domain":"gaming","difficulty":.3,"current_information":true}).allowed)
	assert(Knowledge.assess(stanley,{},"How do I find the derivative?",{"domain":"math","difficulty":.35}).allowed)
	var student_names:={}
	var opposites:=false
	for index in 80:
		var student:=Profiles.student(index)
		assert(Profiles.student(index)==student,"Stable generation: "+str(index))
		assert(student.beliefs.size()==5)
		student_names[student.name]=true
		if float(student.traits.confidence)>.7 and float(student.traits.shyness)>.65:opposites=true
	assert(student_names.size()>50,str(student_names.size()))
	assert(opposites,"Independently generated confidence and shyness should allow unusual combinations")
	assert(Profiles.student(0).name=="Sam Singh","Legacy identity migration")
	var model:=Toon.build(Toon.defaults())
	root.add_child(model)
	var animation:=model.get_node("AnimationPlayer") as AnimationPlayer
	animation.stop()
	var rig:=Motion._rig(model)
	assert(rig.eyes.size()>=2,"Actual Toon eye meshes or grouped eye rigs must be found")
	assert(rig.brows.size()==4,"Actual Toon eyebrow links must be found")
	assert(rig.mouth.size()>=16,"Actual Toon mouth links must be found")
	var eye:Node3D=rig.eyes[0].node
	var original_scale:Vector3=rig.eyes[0].scale
	Motion.express(model,"angry",1.,"argue",1.,Vector3.INF,{"anger":.9,"irritation":.8},brian.traits)
	assert(eye.scale.y<original_scale.y*.8,"Anger must visibly narrow actual eye mesh")
	assert(absf(model.get_node("Body").rotation.x)>.01,"Mood must affect posture")
	assert(absf(model.get_node("Body/ArmL").rotation.x)>.3,"Argument uses both arms")
	var outer_brow: MeshInstance3D=rig.brows[0].node
	var inner_brow: MeshInstance3D=rig.brows[1].node
	var outer: Vector3=outer_brow.position-outer_brow.basis.y*outer_brow.mesh.height*.5
	var inner: Vector3=inner_brow.position+inner_brow.basis.y*inner_brow.mesh.height*.5
	assert(inner.y<outer.y,"Anger lowers the inner brow rather than breaking the individual links")
	Motion.express(model,"happy",1.,"celebrate",2.,Vector3.INF,{"happiness":.9},bro.traits)
	assert(absf(model.get_node("Body/ArmR").rotation.z)>1.5,"Celebration must be visible")
	assert(rig.mouth[0].node.position.y>rig.mouth[7].node.position.y,"Happiness raises the mouth corners")
	Motion.express(model,"sad",1.,"defensive",2.,Vector3.INF,{"sadness":.95,"anxiety":.7},{"expressiveness":.85})
	assert(rig.mouth[0].node.position.y<rig.mouth[7].node.position.y,"Hurt must overcome an authored smiling mouth")
	outer=outer_brow.position-outer_brow.basis.y*outer_brow.mesh.height*.5
	inner=inner_brow.position+inner_brow.basis.y*inner_brow.mesh.height*.5
	assert(inner.y>outer.y,"Hurt raises the inner brow distinctly from anger")
	for index in range(rig.mouth.size()-1):
		var first: MeshInstance3D=rig.mouth[index].node
		var second: MeshInstance3D=rig.mouth[index+1].node
		var end: Vector3=first.position+first.basis.y*first.mesh.height*.5
		var start: Vector3=second.position-second.basis.y*second.mesh.height*.5
		assert(end.distance_to(start)<.001,"Emotional lip links must remain joined")
		assert(absf(first.basis.x.dot(first.basis.y))<.001,"Lip changes must not shear the mesh basis")
	Motion.express(model,"interested",1.,"phone",2.)
	var left_hand: Node3D=model.get_node("Body/ArmL/Hand")
	var right_hand: Node3D=model.get_node("Body/ArmR/Hand")
	assert(absf(left_hand.global_position.x-right_hand.global_position.x)<.35,"The phone pose holds the hands together in front of the body")
	Motion.express(model,"steady",1.,"",3.)
	assert(eye.scale.distance_to(original_scale)<.0001,"Restored expression preserves authored proportions")
	for pose in Motion.POSES:Motion.express(model,"steady",.1,pose,1.)
	model.queue_free()
	print("CHARACTER_WORLDVIEWS PASS: 21 teachers; multi-turn diverse conflict; 80 stable students; slow affect; semantic knowledge; real rig eyes/brows/mouth/arms/posture")
	quit(0)
