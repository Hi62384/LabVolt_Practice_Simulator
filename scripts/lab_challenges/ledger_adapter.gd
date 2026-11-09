extends RefCounted
const Catalog = preload("res://scripts/lab_challenges/scenario_catalog.gd")
const Profile = preload("res://scripts/electronics_profile.gd")
const Decor = preload("res://scripts/lab_challenges/decorations.gd")
const LIMIT_HISTORY := 200
const LIMIT_PROFILES := 256
const LIMIT_MASTERY := 128
var ledger: Object
var authority := Callable()
func available() -> bool:
	return ledger!=null and authority.is_valid() and bool(authority.call())
static func empty() -> Dictionary:
	return {"schema":1,"epoch":Crypto.new().generate_random_bytes(16).hex_encode(),"next_sequence":1,"active":{},"history":[],"progress":{},"decorations":{}}
static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("schema")!=1:return false
	if not value.get("epoch") is String or value.epoch.length()!=32 or not value.epoch.is_valid_hex_number():return false
	if not value.get("next_sequence") is int or value.next_sequence<1 or value.next_sequence>2147483646:return false
	if not value.get("active") is Dictionary or value.active.size()>3 or not value.get("history") is Array or value.history.size()>LIMIT_HISTORY:return false
	if not value.get("progress") is Dictionary or value.progress.size()>LIMIT_PROFILES or not value.get("decorations") is Dictionary or value.decorations.size()>3:return false
	for identity in value.progress:
		if not identity is String or identity.length()!=48 or not identity.is_valid_hex_number():return false
		var profile: Variant=value.progress[identity]
		if not profile is Dictionary or not profile.get("mastery") is Dictionary or profile.mastery.size()>LIMIT_MASTERY or not profile.get("count") is int or profile.count!=profile.mastery.size() or not profile.get("kinds") is Dictionary:return false
		var total := 0
		for kind in profile.kinds:
			if kind not in Catalog.KINDS or not profile.kinds[kind] is int or profile.kinds[kind]<0 or profile.kinds[kind]>LIMIT_MASTERY:return false
			total+=profile.kinds[kind]
		if total!=profile.count:return false
		for key in profile.mastery:
			if not key is String or key.length()>64 or profile.mastery[key]!=true:return false
	for key in value.active:
		if key not in ["0","1","2"] or not _attempt(value.active[key],value) or int(value.active[key].bench)!=int(key):return false
	for record in value.history:
		if not _attempt(record,value) or record.get("outcome") not in ["completed","abandoned"]:return false
	for bench in value.decorations:
		if bench not in ["0","1","2"] or not value.decorations[bench] is Dictionary or value.decorations[bench].size()>2:return false
		for anchor in value.decorations[bench]:
			var selection: Variant=value.decorations[bench][anchor]
			if anchor not in Decor.ANCHORS or not selection is Dictionary or selection.get("id") not in Decor.DEFINITIONS or not selection.get("owner") is String:return false
			if selection.id not in Decor.unlocks(value.progress.get(selection.owner,{})):return false
	return var_to_bytes(value).size()<=8388608
static func _attempt(entry: Variant, root_value: Dictionary) -> bool:
	if not entry is Dictionary or not entry.get("bench") is int or entry.bench<0 or entry.bench>2 or not entry.get("difficulty") is int or entry.difficulty<0 or entry.difficulty>2 or entry.get("kind") not in Catalog.KINDS or not entry.get("seed") is int or entry.seed<0 or entry.seed>2147483647:return false
	if not entry.get("sequence") is int or entry.sequence<1 or entry.sequence>=root_value.next_sequence:return false
	if entry.get("id")!="labteam:"+str(root_value.epoch)+":"+str(entry.sequence):return false
	if not entry.get("participants") is Array or entry.participants.size()<2 or entry.participants.size()>8 or not entry.get("evidence") is Dictionary or entry.evidence.size()>8:return false
	if not entry.get("roles") is Dictionary or entry.roles.size()!=entry.participants.size() or not entry.get("names") is Dictionary or entry.names.size()!=entry.participants.size():return false
	var seen := {}
	for identity in entry.participants:
		if not identity is String or identity.length()!=48 or not identity.is_valid_hex_number() or seen.has(identity):return false
		seen[identity]=true
		if entry.roles.get(identity) not in ["repair","verify","measure_final"] or not entry.names.get(identity) is String or entry.names[identity].length()>24:return false
	for identity in entry.evidence:
		if identity not in seen or not entry.evidence[identity] is Dictionary or entry.evidence[identity].size()>4:return false
		for key in entry.evidence[identity]:
			if key not in ["repair","verify","measure_final","measure_fault"] or not entry.evidence[identity][key] is bool:return false
	var measurements: Variant=entry.get("measurements",{})
	if not measurements is Dictionary:return false
	for key in measurements:
		if key in ["voltmeters","ammeters","wattmeters"]:
			var count := 2 if key=="wattmeters" else 3
			if not measurements[key] is Array or measurements[key].size()!=count:return false
			for number in measurements[key]:
				if not (number is float or number is int) or not is_finite(float(number)) or absf(float(number))>1e6:return false
		elif key in ["p","q","pf","motor_rpm"]:
			if not (measurements[key] is float or measurements[key] is int) or not is_finite(float(measurements[key])) or absf(float(measurements[key]))>1e6:return false
		else:return false
	return entry.get("diagnosis","") is String and str(entry.get("diagnosis","")).length()<=64
func root() -> Dictionary:
	if not available():return {}
	var value: Variant=ledger.state.get("lab_challenges")
	return empty() if value==null else value.duplicate(true) if valid(value) else {}
func commit(root_value: Dictionary) -> bool:
	if not available() or not valid(root_value):return false
	var next: Dictionary=ledger.state.duplicate(true);next.lab_challenges=root_value.duplicate(true)
	return bool(ledger.persist(next))
func complete(bench: int, attempt_id: String, measurements: Dictionary, now: int) -> Dictionary:
	var root_value := root();var key := str(bench)
	if root_value.is_empty() or not root_value.active.has(key):return {"ok":false,"error":"No active team attempt."}
	var attempt: Dictionary=root_value.active[key]
	if attempt.id!=attempt_id:return {"ok":false,"error":"Stale attempt."}
	var next: Dictionary=ledger.state.duplicate(true);var rewards := {}
	var mastery := str(attempt.kind)+":"+str(attempt.seed)
	for identity in attempt.participants:
		if not next.accounts.has(identity) or not next.accounts[identity].profile.get("pending_trade",{}).is_empty():return {"ok":false,"error":"A participant profile is unavailable or trading."}
		if not root_value.progress.has(identity):
			if root_value.progress.size()>=LIMIT_PROFILES:return {"ok":false,"error":"Challenge progress capacity reached."}
			root_value.progress[identity]={"count":0,"kinds":{},"mastery":{}}
		var progress: Dictionary=root_value.progress[identity]
		var amount := 0
		if not progress.mastery.has(mastery) and progress.mastery.size()<LIMIT_MASTERY:
			var profile := Profile.new();profile.data=next.accounts[identity].profile.duplicate(true)
			var reward_id := "labteam:"+mastery.sha256_text()
			var claimed: bool=profile.data.reward_ids.has(reward_id)
			amount=profile.reward(reward_id,100.0,int(attempt.difficulty),false)
			if (not profile.data.reward_ids.has(reward_id) and not claimed) or not Profile.valid(profile.data):return {"ok":false,"error":"Challenge reward could not be committed."}
			next.accounts[identity].profile=profile.data;next.accounts[identity].revision+=1
			progress.mastery[mastery]=true;progress.count+=1;progress.kinds[attempt.kind]=int(progress.kinds.get(attempt.kind,0))+1
		rewards[identity]=amount
	var record := {"id":attempt.id,"sequence":attempt.sequence,"bench":attempt.bench,"kind":attempt.kind,"seed":attempt.seed,"participants":attempt.participants.duplicate(),"roles":attempt.roles.duplicate(true),"names":attempt.names.duplicate(true),"difficulty":attempt.difficulty,"outcome":"completed","completed_at":now,"measurements":measurements.duplicate(true),"rewards":rewards,"diagnosis":attempt.diagnosis,"evidence":attempt.evidence.duplicate(true)}
	root_value.active.erase(key);root_value.history.append(record)
	while root_value.history.size()>LIMIT_HISTORY:root_value.history.pop_front()
	if not valid(root_value):return {"ok":false,"error":"Team record exceeds safe limits."}
	next.lab_challenges=root_value
	if not ledger.persist(next):return {"ok":false,"error":"Host save failed; team result and rewards were not applied."}
	return {"ok":true,"record":record}
