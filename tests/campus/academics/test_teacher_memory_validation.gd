extends SceneTree
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
const PATH="user://teacher_memory_validation_fixture.json"
var student: String="a".repeat(48)

func _write(path: String,contents: String) -> void:
 var file:=FileAccess.open(path,FileAccess.WRITE)
 assert(file!=null)
 file.store_string(contents);file.close()

func _record(entry: Dictionary,extra: Dictionary={}) -> String:
 var document:={"version":1,"relationships":{}}
 document.relationships["jeff:"+student]=entry
 document.merge(extra)
 return JSON.stringify(document)

func _brain() -> RefCounted:
 var brain=Brain.new();brain.memory_path=PATH
 return brain

func _initialize() -> void:
 for suffix in ["",".bak",".tmp"]:
  DirAccess.remove_absolute(PATH+suffix)
 var entry:={"familiarity":2,"positive":1,"disruptions":0,"last_seen":100000,"decay_at":100000}
 var brain=_brain();brain.remember("jeff",student,"help",100000)
 assert(brain.save_memory()==OK)
 var roundtrip=_brain();roundtrip.load_memory()
 assert(roundtrip.relationship("jeff",student).positive==1 and not roundtrip.memory_blocked)
 _write(PATH,_record(entry))
 var valid=_brain();valid.load_memory()
 assert(valid.relationship("jeff",student).last_seen==100000)
 var malformed=[
  _record({"familiarity":100.9,"positive":1,"disruptions":0,"last_seen":100000}),
  _record({"familiarity":2,"positive":1,"disruptions":0,"last_seen":100000.5}),
  _record({"familiarity":101,"positive":1,"disruptions":0,"last_seen":100000}),
  _record({"familiarity":2,"positive":1,"disruptions":21,"last_seen":100000}),
  _record({"familiarity":2,"positive":1,"disruptions":0,"last_seen":100000,"extra":0}),
  _record(entry,{"unexpected":true}),
  '{broken json'
 ]
 for bad in malformed:
  _write(PATH,bad);DirAccess.remove_absolute(PATH+".bak")
  valid=_brain()
  valid.load_memory()
  assert(valid.relationships.is_empty() and valid.memory_blocked)
  valid.remember("jeff",student,"help",200000)
  assert(valid.save_memory()!=OK and FileAccess.get_file_as_string(PATH)==bad)
  assert(not valid.retry_memory_load() and valid.relationship("jeff",student).positive==1)
  assert(FileAccess.get_file_as_string(PATH)==bad)
 _write(PATH,_record(entry));DirAccess.remove_absolute(PATH+".bak")
 var legacy=_record({"familiarity":2,"positive":1,"disruptions":2,"last_seen":100000})
 _write(PATH,legacy)
 var migrated=_brain();migrated.load_memory()
 assert(migrated.relationship("jeff",student).decay_at==100000)
 migrated.remember("jeff",student,"conversation",100000+86400-1)
 assert(migrated.relationship("jeff",student).disruptions==2)
 migrated.remember("jeff",student,"conversation",100000+86400)
 assert(migrated.relationship("jeff",student).disruptions==1)
 _write(PATH+".bak",_record(entry));_write(PATH,"{broken json")
 var recovered=_brain();recovered.load_memory()
 assert(recovered.relationship("jeff",student).positive==1 and recovered.memory_dirty)
 assert(recovered.save_memory()==OK and _brain()._read_memory(PATH).ok)
 _write(PATH,"{broken json");_write(PATH+".bak","{broken json")
 recovered.load_memory()
 assert(recovered.relationships.is_empty() and recovered.memory_blocked)
 assert(recovered.save_memory()!=OK)
 DirAccess.remove_absolute(PATH);DirAccess.remove_absolute(PATH+".bak")
 var failed=_brain();failed.remember("jeff",student,"help",100000)
 assert(DirAccess.make_dir_absolute(PATH+".tmp")==OK)
 assert(failed.save_memory()!=OK and failed.memory_dirty)
 DirAccess.remove_absolute(PATH+".tmp")
 assert(DirAccess.make_dir_absolute(PATH)==OK)
 assert(failed.save_memory()!=OK and failed.memory_dirty)
 DirAccess.remove_absolute(PATH)
 assert(failed.save_memory()==OK and not failed.memory_dirty)
 var isolated=_brain();isolated.load_memory()
 assert(isolated.relationship("jeff",student).positive==1)
 assert(isolated.relationship("jeff","b".repeat(48)).positive==0)
 assert(isolated.relationship("bill",student).positive==0)
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(PATH+suffix)
 print("TEACHER_MEMORY_VALIDATION PASS")
 quit(0)
