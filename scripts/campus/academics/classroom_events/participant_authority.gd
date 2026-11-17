extends RefCounted
## Caller must derive peer from the server's RPC sender and compute inside on host.
static func resolve(peer: int,roster: Dictionary,identities: Dictionary,activity: Dictionary,inside: bool) -> String:
 if peer<=0 or not inside or not roster.has(peer) or activity.get("phase","")!="lesson":return ""
 var identity:=str(identities.get(peer,""))
 if identity.is_empty():return ""
 var students: Variant=activity.get("students",{})
 if not students is Dictionary:return ""
 var student: Variant=students.get(identity,{})
 if not student is Dictionary or student.is_empty() or int(student.get("peer",0))!=peer or student.get("done",false):return ""
 return identity
