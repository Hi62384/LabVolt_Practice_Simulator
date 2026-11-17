extends SceneTree
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
const PATH="user://teacher_memory_bounds_fixture.json"
func _initialize() -> void:
 var brain:=Brain.new()
 brain.memory_path=PATH
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(PATH+suffix)
 for i in Brain.MAX_RELATIONSHIPS:
  brain.remember("teacher","student_%d"%i,"conversation",100000)
 brain.remember("teacher","overflow","help",100000)
 assert(brain.relationships.size()==Brain.MAX_RELATIONSHIPS)
 assert(not brain.relationships.has("teacher:overflow"))
 for i in 110:brain.remember("teacher","student_0","help",100001+i)
 assert(brain.relationship("teacher","student_0").positive==100)
 assert(brain.relationship("teacher","student_0").familiarity==100)
 for i in 30:brain.remember("teacher","student_1","disruption",100001+i)
 assert(brain.relationship("teacher","student_1").disruptions==20)
 assert(brain.relationship("teacher","student_0").disruptions==0)
 assert(brain.save_memory()==OK)
 var loaded:=Brain.new();loaded.memory_path=PATH;loaded.load_memory()
 assert(loaded.relationships.size()==Brain.MAX_RELATIONSHIPS)
 assert(loaded.relationship("teacher","student_1").disruptions==20)
 var file:=FileAccess.open(PATH,FileAccess.WRITE)
 file.store_string('{"version":1,"relationships":{"bad":{"last_seen":-1}}}')
 file.close();loaded.load_memory()
 assert(loaded.relationships.is_empty() and loaded.memory_blocked)
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(PATH+suffix)
 print("TEACHER_MEMORY_BOUNDS PASS")
 quit(0)
