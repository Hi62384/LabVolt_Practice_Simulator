extends "res://scripts/campus/academics/character_memory.gd"
## Pure event evaluation. Call only for authenticated, perceived events on the host.
## CharacterMemory owns durable, directional social history; discipline remains
## host-authoritative and does not modify grading.
var teachers:={}
var incidents:={}
var reaction_times:={}
const COOLDOWN_MS:=12000
const MAX_REACTION_KEYS:=2048
const MAX_INCIDENT_KEYS:=2048

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

func consider(id: String,student: String,kind: String,severity: float,personality: Dictionary,now_ms: int,roll: float,audibility: float=1.0,record_memory: bool=true) -> Dictionary:
 if id.is_empty() or student.is_empty() or kind not in ["lab_hazard","class_message","addressed_speech","voice_noise","ambient_speech","phone_use","seat_departure","thrown_object"]:return {}
 if id.length()+student.length()+1>128:return {}
 if not is_finite(severity) or not is_finite(roll) or not is_finite(audibility):return {}
 severity=clampf(severity,0.,1.)
 audibility=clampf(audibility,0.,1.)
 # Disposition can influence attention, never create hearing through a wall or
 # make an inaudible event count as an observed student action.
 if audibility<=0.:return {}
 var state: Dictionary=teachers.get(id,{"frustration":0.0,"last_update":now_ms,"last_reaction":-45000})
 var elapsed:=maxf(0.0,float(now_ms-int(state.last_update))/1000.0)
 state.frustration=maxf(0.0,float(state.frustration)-elapsed*(.7+.6*_personality_trait(personality,"emotional_stability"))/180.0)
 state.last_update=now_ms
 var difficulty:=_personality_trait(personality,"strictness",_personality_number(personality.get("difficulty"),.5))
 var focus:=_personality_trait(personality,"focus",_personality_number(personality.get("focus"),.5))
 var talk:=_personality_trait(personality,"talkativeness",_personality_number(personality.get("talkativeness"),.5))
 var patience:=_personality_trait(personality,"patience")
 var sensitivity:=_personality_trait(personality,"anger_sensitivity")
 var attention_span:=_personality_trait(personality,"attention_span")
 var motivation:=_personality_trait(personality,"teaching_motivation",_personality_trait(personality,"teaching_effort"))
 var laziness:=_personality_trait(personality,"laziness")
 var key:=id+":"+student
 var memory: Dictionary=incidents.get(key,{"count":0,"last":0,"kind":""})
 if kind in ["class_message","voice_noise"] and str(memory.get("kind","")) in ["class_message","voice_noise"] and str(memory.get("kind",""))!=kind and now_ms-int(memory.last)<2000:return {}
 var awareness:=.2+.45*focus+.45*severity
 if kind!="lab_hazard":
  awareness*=clampf(1.+.3*(attention_span-.5)+.2*(motivation-.5)-.25*(laziness-.5),.55,1.3)
  awareness+=.15*(sensitivity-.5)
 var notice:=clampf(awareness*audibility,0.0,1.0)
 if kind=="ambient_speech":notice*=.18*talk*(.65+.7*_personality_trait(personality,"sociability"))
 if notice<=0. or roll>notice:
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
 if record_memory:remember(id,student,"disruption" if kind in ["class_message","voice_noise","phone_use","seat_departure","thrown_object"] else ("hazard" if kind=="lab_hazard" else "conversation"),int(Time.get_unix_time_from_system()))
 if kind in ["class_message","voice_noise","lab_hazard","phone_use","seat_departure","thrown_object"]:
  state.frustration=clampf(float(state.frustration)+severity*(.08+.20*difficulty)*(1.+.55*(sensitivity-.5)-.45*(patience-.5)),0.0,1.0)
 teachers[id]=state
 var reaction_cooldown:=45000 if kind=="ambient_speech" else COOLDOWN_MS
 if now_ms-int(reaction_times.get(key,-45000))<reaction_cooldown or now_ms-int(state.last_reaction)<2000:return {}
 var utility:=severity*(.4+.6*difficulty)+float(state.frustration)*.25
 if kind in ["class_message","voice_noise","phone_use","seat_departure"]:utility+=minf(.3,maxi(0,int(memory.count)-1)*.05)
 if kind!="lab_hazard":
  utility+=.18*(_personality_trait(personality,"confrontation")-.5)+.12*(_personality_trait(personality,"discipline")-.5)+.1*(sensitivity-.5)-.12*(patience-.5)-.1*(_personality_trait(personality,"empathy")-.5)
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

static func _personality_number(value: Variant,fallback: float) -> float:
 if not (value is float or value is int) or not is_finite(float(value)):return fallback
 return clampf(float(value),0.,1.)

static func _personality_trait(personality: Dictionary,key: String,fallback: float=.5) -> float:
 var values: Variant=personality.get("traits",{})
 if values is Dictionary and values.has(key):return _personality_number(values[key],fallback)
 return _personality_number(personality.get(key),fallback)

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
