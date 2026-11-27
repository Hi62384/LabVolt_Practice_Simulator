extends RefCounted
## Pure event evaluation. Call only for authenticated, perceived events on the host.
var teachers:={}
var incidents:={}
var reaction_times:={}
var relationships:={}
var conversations:={}
var memory_dirty:=false
var memory_blocked:=false
const COOLDOWN_MS:=12000
const MEMORY_PATH:="user://faculty_relationships.json"
var memory_path: String=MEMORY_PATH
const MAX_RELATIONSHIPS:=2048
const MAX_REACTION_KEYS:=2048
const MAX_INCIDENT_KEYS:=2048
const MAX_CONVERSATIONS:=64
const MAX_TURNS:=12

static func context_allows(kind: String,phase: String,severity: float) -> bool:
 if kind=="class_message":return phase in ["lesson","assignment"]
 if kind=="phone_use":return phase in ["lesson","assignment"]
 if kind=="seat_departure":return phase=="lesson"
 if kind=="voice_noise":return phase in ["lesson","assignment"] or severity>=.6
 return true

## Audible events attenuate with distance and intervening solid geometry.
## A circuit fault is louder than conversation; neither is campus-wide.
static func audibility(kind: String,distance: float,obstructed: bool) -> float:
 if not is_finite(distance) or distance<0.0:return 0.0
 var reach:=10.0 if kind=="lab_hazard" else 7.0
 if distance>=reach:return 0.0
 var strength:=1.0-distance/reach
 if obstructed:strength*=0.25
 return clampf(strength,0.0,1.0)

## Sight is restricted by distance, facing and a clear line of sight.
static func visibility(origin: Vector3,forward: Vector3,point: Vector3,obstructed: bool) -> float:
 if obstructed or not origin.is_finite() or not forward.is_finite() or not point.is_finite():return 0.0
 var offset:=point-origin;offset.y=0.0;forward.y=0.0
 var distance:=offset.length()
 if distance>=10.0 or forward.length_squared()<.0001:return 0.0
 if distance<.001:return 1.0
 var facing:=forward.normalized().dot(offset/distance)
 if facing<.5:return 0.0
 return clampf((1.0-distance/10.0)*facing,0.0,1.0)

func relationship(id: String,student: String) -> Dictionary:
 return relationships.get(id+":"+student,{"familiarity":0,"positive":0,"disruptions":0,"last_seen":0,"decay_at":0}).duplicate(true)

func recall(id: String,student: String) -> Array:
 return conversations.get(id+":"+student,[]).duplicate(true)

func remember_conversation(id: String,student: String,question: String,reply: String,now: int) -> void:
 if id.is_empty() or student.is_empty() or memory_blocked:return
 var key:=id+":"+student
 if key.length()>128 or (not relationships.has(key) and relationships.size()>=MAX_RELATIONSHIPS):return
 if conversations.size()>=MAX_CONVERSATIONS and not conversations.has(key):
  conversations.erase(conversations.keys()[0])
 var turns: Array=conversations.get_or_add(key,[])
 turns.append({"student":question.left(220),"teacher":reply.left(320)})
 while turns.size()>MAX_TURNS:turns.pop_front()
 remember(id,student,"conversation",now)
 memory_dirty=true

func remember(id: String,student: String,kind: String,now_unix: int) -> void:
 if id.is_empty() or student.is_empty() or kind not in ["conversation","help","disruption","hazard","competition"]:return
 var key:=id+":"+student
 if key.length()>128:return
 if not relationships.has(key) and relationships.size()>=MAX_RELATIONSHIPS:return
 var memory:=relationship(id,student)
 var decay_at:=int(memory.get("decay_at",memory.last_seen))
 if decay_at<=0:decay_at=now_unix
 var days:=int(maxi(0,now_unix-decay_at)/86400)
 # Keep partial days across ordinary conversations instead of restarting the clock.
 memory.disruptions=maxi(0,int(memory.disruptions)-days)
 memory.decay_at=decay_at+days*86400
 memory.familiarity=mini(100,int(memory.familiarity)+1)
 if kind=="help":memory.positive=mini(100,int(memory.positive)+1)
 elif kind=="competition":memory.competitions=mini(20,int(memory.get("competitions",0))+1)
 elif kind=="disruption":
  if int(memory.disruptions)==0:memory.decay_at=now_unix
  memory.disruptions=mini(20,int(memory.disruptions)+1)
 memory.last_seen=now_unix;relationships[key]=memory;memory_dirty=true

func load_memory() -> bool:
 # Never replace newer, unsaved observations with an older disk snapshot.
 if memory_dirty:return false
 relationships={};conversations={};memory_dirty=false;memory_blocked=false
 var primary_exists:=FileAccess.file_exists(memory_path)
 var backup_exists:=FileAccess.file_exists(memory_path+".bak")
 var loaded:=_read_memory(memory_path)
 var recovered:=false
 if not loaded.ok:
  loaded=_read_memory(memory_path+".bak")
  recovered=loaded.ok
 if loaded.ok:
  relationships=loaded.relationships
  conversations=loaded.get("conversations",{})
  memory_dirty=recovered
 else:memory_blocked=primary_exists or backup_exists
 return loaded.ok or not memory_blocked

func retry_memory_load() -> bool:
 return load_memory()

func _whole(value: Variant,maximum: int) -> bool:
 if not (value is int or value is float):return false
 var number:=float(value)
 return is_finite(number) and number>=0.0 and number<=float(maximum) and number==floor(number)

func _validate_relationships(source: Variant) -> Dictionary:
 if not source is Dictionary or source.size()>MAX_RELATIONSHIPS:return {"ok":false}
 var validated:={}
 for key in source:
  var entry: Variant=source[key]
  if not key is String or key.length()>128 or key.find(":")<=0 or key.ends_with(":") or not entry is Dictionary or entry.size() not in [4,5,6]:return {"ok":false}
  for character in key:
   if character.unicode_at(0)<32:return {"ok":false}
  for field in ["familiarity","positive","disruptions","last_seen"]:
   if not entry.has(field):return {"ok":false}
  for field in entry:
   if field not in ["familiarity","positive","disruptions","last_seen","decay_at","competitions"]:return {"ok":false}
  if not _whole(entry.familiarity,100) or not _whole(entry.positive,100) or not _whole(entry.disruptions,20) or not _whole(entry.last_seen,100000000000):return {"ok":false}
  if entry.has("decay_at") and not _whole(entry.decay_at,100000000000):return {"ok":false}
  validated[key]={"familiarity":int(entry.familiarity),"positive":int(entry.positive),"disruptions":int(entry.disruptions),"last_seen":int(entry.last_seen),"decay_at":int(entry.get("decay_at",entry.last_seen))}
  if entry.has("competitions"):
   if not _whole(entry.competitions,20):return {"ok":false}
   validated[key].competitions=int(entry.competitions)
 return {"ok":true,"relationships":validated}

func _read_memory(path: String) -> Dictionary:
 if not FileAccess.file_exists(path):return {"ok":false}
 var file:=FileAccess.open(path,FileAccess.READ)
 if file==null or file.get_length()>1024*1024:return {"ok":false}
 var parser:=JSON.new()
 if parser.parse(file.get_as_text())!=OK:return {"ok":false}
 var value: Variant=parser.data
 if not value is Dictionary or not value.has("relationships"):return {"ok":false}
 if value.get("version")==1 and value.size()==2:return _validate_relationships(value.relationships)
 if value.get("version")!=2 or value.size()!=3:return {"ok":false}
 var validated:=_validate_relationships(value.relationships)
 var turns: Variant=value.get("conversations")
 if not validated.ok or not turns is Dictionary or turns.size()>MAX_CONVERSATIONS:return {"ok":false}
 for key in turns:
  if not key is String or not validated.relationships.has(key) or not turns[key] is Array or turns[key].size()>MAX_TURNS:return {"ok":false}
  for exchange in turns[key]:
   if not exchange is Dictionary or exchange.size()!=2 or not exchange.get("student") is String or not exchange.get("teacher") is String:return {"ok":false}
   if exchange.student.length()>220 or exchange.teacher.length()>320:return {"ok":false}
 validated.conversations=turns
 return validated

func save_memory() -> Error:
 if memory_blocked:return ERR_FILE_CORRUPT
 if not memory_dirty:return OK
 var validated:=_validate_relationships(relationships)
 if not validated.ok:return ERR_INVALID_DATA
 var file:=FileAccess.open(memory_path+".tmp",FileAccess.WRITE)
 if file==null:return FileAccess.get_open_error()
 var snapshot:={"version":1,"relationships":validated.relationships}
 if not conversations.is_empty():
  snapshot.version=2
  # A remembered dialogue always belongs to an existing relationship record.
  snapshot.conversations=conversations
 file.store_string(JSON.stringify(snapshot));file.flush()
 var error:=file.get_error();file.close()
 if error!=OK:return error
 # A corrupt primary must never overwrite the last valid backup.
 if FileAccess.file_exists(memory_path) and _read_memory(memory_path).ok:
  error=DirAccess.copy_absolute(memory_path,memory_path+".bak")
  if error!=OK:return error
 error=DirAccess.rename_absolute(memory_path+".tmp",memory_path)
 if error==OK:memory_dirty=false
 return error
func consider(id: String,student: String,kind: String,severity: float,personality: Dictionary,now_ms: int,roll: float,audibility: float=1.0) -> Dictionary:
 if id.is_empty() or student.is_empty() or kind not in ["lab_hazard","class_message","addressed_speech","voice_noise","ambient_speech","phone_use","seat_departure","thrown_object"]:return {}
 if id.length()+student.length()+1>128:return {}
 var state: Dictionary=teachers.get(id,{"frustration":0.0,"last_update":now_ms,"last_reaction":-45000})
 var elapsed:=maxf(0.0,float(now_ms-int(state.last_update))/1000.0)
 state.frustration=maxf(0.0,float(state.frustration)-elapsed/180.0)
 state.last_update=now_ms
 var difficulty: float=float(personality.get("difficulty",.5)) if personality.get("difficulty")!=null else .9
 var focus: float=float(personality.get("focus",.5)) if personality.get("focus")!=null else .5
 var talk: float=float(personality.get("talkativeness",.5)) if personality.get("talkativeness")!=null else .5
 var traits:=str(personality.get("description","")).to_lower()
 var key:=id+":"+student
 var memory: Dictionary=incidents.get(key,{"count":0,"last":0,"kind":""})
 if kind in ["class_message","voice_noise"] and str(memory.get("kind","")) in ["class_message","voice_noise"] and str(memory.get("kind",""))!=kind and now_ms-int(memory.last)<2000:return {}
 var notice:=clampf((.2+.45*focus+.45*severity)*clampf(audibility,0.0,1.0),0.0,1.0)
 if kind=="ambient_speech":notice*=.18*clampf(talk,0.0,1.0)
 if kind!="lab_hazard" and "disengagement" in traits:notice*=.65
 if kind!="lab_hazard" and "short temper" in traits:notice=minf(1.0,notice+.12)
 if roll>notice:
  teachers[id]=state
  return {}
 if kind in ["class_message","voice_noise","lab_hazard","phone_use","seat_departure","thrown_object"]:
  if not incidents.has(key) and incidents.size()>=MAX_INCIDENT_KEYS:
   var oldest_incident: String=""
   var oldest_incident_time:=now_ms
   for previous in incidents:
    if int(incidents[previous].get("last",0))<=oldest_incident_time:oldest_incident=str(previous);oldest_incident_time=int(incidents[previous].get("last",0))
   if not oldest_incident.is_empty():incidents.erase(oldest_incident)
  memory.count=mini(20,int(memory.count)+1);memory.last=now_ms;memory.kind=kind;incidents[key]=memory
 remember(id,student,"disruption" if kind in ["class_message","voice_noise","phone_use","seat_departure","thrown_object"] else ("hazard" if kind=="lab_hazard" else "conversation"),int(Time.get_unix_time_from_system()))
 if kind in ["class_message","voice_noise","lab_hazard","phone_use","seat_departure","thrown_object"]:state.frustration=clampf(float(state.frustration)+severity*(.08+.20*difficulty),0.0,1.0)
 teachers[id]=state
 var reaction_cooldown:=45000 if kind=="ambient_speech" else COOLDOWN_MS
 if now_ms-int(reaction_times.get(key,-45000))<reaction_cooldown or now_ms-int(state.last_reaction)<2000:return {}
 var utility:=severity*(.4+.6*difficulty)+float(state.frustration)*.25
 if kind in ["class_message","voice_noise","phone_use","seat_departure"]:utility+=minf(.3,maxi(0,int(memory.count)-1)*.05)
 if kind!="lab_hazard" and "short temper" in traits:utility+=.16
 if kind!="lab_hazard" and "military bearing" in traits:utility+=.08
 if kind!="lab_hazard" and ("friendly jokes" in traits or "warm encouragement" in traits):utility=minf(utility,.64)
 if kind=="class_message" and utility<.25:return {}
 state.last_reaction=now_ms
 teachers[id]=state
 if not reaction_times.has(key) and reaction_times.size()>=MAX_REACTION_KEYS:
  var oldest_key: String=""
  var oldest_time:=now_ms
  for previous in reaction_times:
   if int(reaction_times[previous])<=oldest_time:oldest_key=str(previous);oldest_time=int(reaction_times[previous])
  if not oldest_key.is_empty():reaction_times.erase(oldest_key)
 reaction_times[key]=now_ms
 return {"intent":"hazard" if kind=="lab_hazard" else ("throw" if kind=="thrown_object" else ("chat" if kind in ["addressed_speech","ambient_speech"] else ("seat_departure" if kind=="seat_departure" else ("phone" if kind=="phone_use" else ("noise" if kind=="voice_noise" else "class_message"))))),"level":"firm" if utility>.65 else "calm","student":student}

## A perceived, teacher-addressed apology can ease one recent warning. It does
## not erase the student's longer-lived relationship history or any grade.
func accept_apology(id: String,student: String,now_ms: int) -> bool:
 var key:=id+":"+student
 var incident: Dictionary=incidents.get(key,{})
 if id.is_empty() or student.is_empty() or not teachers.has(id) or int(incident.get("count",0))<1 or str(incident.get("kind","")) not in ["class_message","voice_noise","phone_use"]:return false
 if now_ms<int(incident.get("last",0)) or now_ms-int(incident.get("last",0))>60000:return false
 if now_ms-int(incident.get("last_apology",-30000))<30000:return false
 incident.count=maxi(0,int(incident.count)-1)
 incident.last_apology=now_ms
 incidents[key]=incident
 var state: Dictionary=teachers[id]
 state.frustration=maxf(0.0,float(state.frustration)-.12)
 teachers[id]=state
 return true
