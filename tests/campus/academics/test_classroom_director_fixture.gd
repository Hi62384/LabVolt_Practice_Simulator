extends SceneTree
const Director=preload("res://tests/campus/academics/classroom_director_fixture.gd")
func _initialize() -> void:
 var director:=Director.new()
 var definitions:=[{"id":"question","courses":["ETY155"],"weight":2,"seconds":20,"resource":"board"}]
 assert(director.propose(false,"lesson",100,"ETY155",definitions,["one"],0).is_empty())
 assert(director.propose(true,"assignment",100,"ETY155",definitions,["one"],0).is_empty())
 assert(director.propose(true,"lesson",64,"ETY155",definitions,["one"],0).is_empty())
 var event:=director.propose(true,"lesson",100,"ETY155",definitions,["one","two"],0)
 assert(not event.is_empty())
 event.participants.clear();assert(director.event.participants.size()==2)
 assert(not director.advance(false,director.event.id,"preparing"))
 var id: String=director.event.id
 for state in ["preparing","announcing","active","interrupted","active","resolving","complete"]:
  assert(director.advance(true,id,state))
 assert(director.event.is_empty() and director.completed==1)
 assert(not director.advance(true,id,"preparing"))
 definitions.append({"id":"quiz","courses":["ETY155"],"weight":1,"seconds":30,"resource":"projector"})
 var next:=director.propose(true,"lesson",100,"ETY155",definitions,["one","two"],0)
 assert(next.definition=="quiz")
 assert(not director.participant_disconnected(false,"one"))
 assert(director.participant_disconnected(true,"one"))
 assert(director.event.participants==["two"])
 assert(not director.assessment_started(false) and not director.event.is_empty())
 assert(director.assessment_started(true) and director.event.is_empty())
 assert(not director.advance(true,next.id,"preparing"))
 print("CLASSROOM_DIRECTOR_FIXTURE PASS");quit(0)
