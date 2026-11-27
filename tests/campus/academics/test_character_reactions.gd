extends SceneTree

const Characters=preload("res://scripts/campus/academics/class_character_profile.gd")
const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")
const Mind=preload("res://scripts/campus/academics/character_mind.gd")
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
const Affect=preload("res://scripts/campus/academics/character_affect.gd")
const Motion=preload("res://scripts/campus/academics/character_motion.gd")
const Behavior=preload("res://scripts/campus/academics/character_behavior.gd")

func _initialize() -> void:
	var people: Array=Roster.PEOPLE.keys().map(func(id):return Characters.teacher(id))
	for index in [0,2,4,7,9,11]:people.append(Characters.student(index))
	var faculty_greetings: Dictionary={}
	var biographies: Dictionary={}
	var faculty_lessons: Dictionary={}
	for person in people:
		var mind:=Mind.new()
		var brain:=Brain.new()
		var id: String=person.id
		assert(person.traits.size()>=75,id)
		assert(person.traits.values().all(func(value):return is_finite(value) and value>=0. and value<=1.),id)
		assert(Mind.instructions(person,"steady").length()<4500,id)
		assert(not str(person.ambition).is_empty(),id)
		if person.role=="teacher":
			biographies[person.biography.personal_story]=true
			assert(not Behavior.classroom_line(person,"practice").is_empty(),id)
			var lesson:=Behavior.priorities(person,"I'm stuck. Can you explain the equation?",{},"lesson")
			assert(lesson.academic,id)
			faculty_lessons[lesson.goal]=true
		else:
			var stable:=Characters.student(int(id.trim_prefix("campus_student_")))
			assert(stable.biography==person.biography and stable.traits==person.traits,id)
		var greeting:=mind.observe(person,{},"Hi",0,"alex")
		assert(not str(greeting.line).is_empty(),id)
		if person.role=="teacher":faculty_greetings[greeting.line]=true
		assert(not str(mind.observe(person,{},"Tell me a joke",50,"alex").line).is_empty(),id)
		assert(not str(mind.observe(person,{},"You're amazing",80,"alex").line).is_empty(),id)
		assert(not mind.observe(person,{},"I don't think that follows from your example.",90,"alex","disagreement").closed,id)
		assert(not mind.observe(person,{},"That explanation was hard to follow.",95,"alex","criticism").closed,id)
		var first:=mind.observe(person,{},"You're an idiot.",100,"alex")
		assert(not first.closed,id)
		var last: Dictionary
		for index in range(8):
			brain.remember(id,"alex","insult",1000+index)
			last=mind.observe(person,brain.relationship(id,"alex"),"You're an idiot.",200+index*200,"alex")
		assert(last.closed and last.line!=first.line,id)
		assert(mind.observe(person,brain.relationship(id,"alex"),"Another question",2000,"alex").closed,id)
		assert(not mind.observe(person,{},"Hi",2001,"jordan").closed,id)
		assert(not mind.observe(person,brain.relationship(id,"alex"),"I'm sorry",2200,"alex").closed,id)
		assert(not Mind.assess(person,{},"Calculate 84561723 times 81235609 in your head").allowed,id)
	assert(faculty_greetings.size()==Roster.PEOPLE.size())
	assert(biographies.size()==Roster.PEOPLE.size())
	assert(faculty_lessons.size()>=3)
	var stanley:=Characters.teacher("stanley")
	var chad:=Characters.teacher("chad")
	var bird:=Characters.teacher("ms_bird_heart")
	var bro:=Characters.teacher("mr_bro")
	var help:="Can you explain the equation? This class is hard."
	assert(Behavior.priorities(chad,help,{},"lesson").goal=="give_minimum")
	assert(Behavior.priorities(bird,help,{},"lesson").goal=="coach")
	assert(Behavior.classroom_line(bird,"practice")!=Behavior.classroom_line(chad,"practice"))
	assert(Behavior.priorities(bird,help,{},"assignment").goal=="protect_assessment")
	var student:=Characters.student(0)
	student.traits.merge({"attention_span":.1,"impulsiveness":.95,"study_habits":.1,"organization":.1},true)
	assert(Behavior.student_activity(student,{"id":"test","phase":"lesson"},{"action":"listening","turns":1},"bored")=="distracted")
	assert(Behavior.priorities(chad,"How do you escape the matrix?",{},"lesson").goal=="pursue_interest")
	assert(Behavior.priorities(chad,"How do you escape the matrix?",{"resentment":6},"lesson").goal=="return_to_activity")
	assert("315 pounds" in Behavior.fallback(bro,Behavior.priorities(bro,"What's your bench press record?",{},"lesson"),"What's your bench press record?",""))
	assert(Mind.new().emotion(stanley,0)=="tired")
	var affected:=Affect.baseline(stanley.traits)
	assert(affected.size()==16)
	for key in affected:
		assert(Motion.APPEARANCE.has(Affect.EXPRESSION[key]),key)
	Affect.apply(affected,stanley.traits,"setback",1.)
	assert(affected.disappointment>.2 and affected.confidence<float(stanley.traits.confidence))
	Affect.recover(affected,stanley.traits,300.)
	assert(is_equal_approx(affected.confidence,float(stanley.traits.confidence)))
	assert(not Mind.assess(stanley,{},"How much does Fortnite's latest battle pass cost?").allowed)
	assert(not Mind.assess(stanley,{},"Which surgery is indicated?").allowed)
	assert(Mind.assess(stanley,{},"How do I find the derivative of an equation?").allowed)
	var brain:=Brain.new()
	brain.memory_path="user://character_reactions_fixture.json"
	brain.remember_conversation("stanley","alex","My favorite game is Fortnite.","Never played it.",1000)
	brain.remember_fact("stanley","alex","My favorite game is Fortnite.",1000)
	for index in range(35):brain.remember_conversation("stanley","alex","Unrelated question %d"%index,"I see.",1001+index)
	brain.remember_fact("stanley","alex","Actually, my favorite game is Minecraft.",1100)
	var story:="I used to work weekends in a repair shop."
	var details:=Mind.decode_dialogue(JSON.stringify({"speech":"I grew up near a lumber yard.","event":"initiative","memory":story,
		"biography":{"topic":"childhood","detail":"I grew up near a lumber yard."}}))
	brain.remember_conversation("chad","alex",story,str(details.speech),1101)
	brain.remember_dialogue_details(chad,"alex",story+" What was your childhood like?",details,1101)
	brain.remember_dialogue_details(chad,"jordan","Where did you grow up?",
		{"memory":story,"biography":{"topic":"childhood","detail":"I grew up on a farm."}},1102)
	assert(brain.save_memory()==OK)
	var reloaded:=Brain.new()
	reloaded.memory_path=brain.memory_path
	assert(reloaded.load_memory())
	var facts:=reloaded.relevant_facts(reloaded.relationship("stanley","alex"),"gaming")
	assert(facts.size()==1 and "Minecraft" in facts[0].statement and facts[0].source=="speaker_statement")
	assert(reloaded.relevant_facts(reloaded.relationship("stanley","jordan"),"gaming").is_empty())
	assert(reloaded.relevant_facts(reloaded.relationship("mr_stone","alex"),"gaming").is_empty())
	assert(reloaded.character_biography(chad).childhood==details.speech)
	assert(reloaded.relevant_facts(reloaded.relationship("chad","alex"),"mechanics").size()==1)
	assert(reloaded.relevant_facts(reloaded.relationship("chad","jordan"),"mechanics").is_empty())
	print("CHARACTER_REACTIONS PASS")
	quit()
