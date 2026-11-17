extends RefCounted
## Bounded host-owned lifecycle and exclusive room resource reservations.
const EDGES:={
 "proposed":["preparing","cancelled"],
 "preparing":["announcing","cancelled"],
 "announcing":["active","cancelled"],
 "active":["resolving","interrupted","timed_out","cancelled"],
 "interrupted":["active","cancelled","timed_out"],
 "resolving":["complete","cancelled"],
}
var states:={}
var reservations:={}

func begin(id: String,room: String,resources: Array) -> bool:
 if id.is_empty() or room.is_empty() or states.has(id) or resources.size()>8:return false
 var unique:={}
 for resource in resources:
  if not resource is String or resource.is_empty() or unique.has(resource) or reservations.has(room+":"+resource):return false
  unique[resource]=true
 states[id]={"phase":"proposed","room":room,"resources":resources.duplicate()}
 for resource in resources:reservations[room+":"+resource]=id
 return true

func advance(id: String,phase: String) -> bool:
 if not states.has(id) or phase not in EDGES.get(states[id].phase,[]):return false
 states[id].phase=phase
 if phase in ["complete","cancelled","timed_out"]:_release(id)
 return true

func cancel(id: String) -> bool:
 if not states.has(id):return false
 if states[id].phase in ["complete","cancelled","timed_out"]:return false
 return advance(id,"cancelled")

func _release(id: String) -> void:
 for resource in states[id].resources:reservations.erase(states[id].room+":"+resource)

func clear() -> void:
 states.clear();reservations.clear()
