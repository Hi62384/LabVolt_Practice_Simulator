extends RefCounted
## Host-owned hand queue. Public snapshots drive remote avatar gestures while gated.
const MAX_STUDENTS:=32
var event_id: String
var eligible:={}
var present:={}
var hands: Array[String]=[]
var selected: String=""

func begin(host: bool,id: String,students: Array) -> bool:
 if not host or not event_id.is_empty() or id.is_empty() or students.is_empty() or students.size()>MAX_STUDENTS:return false
 var checked:={}
 for student in students:
  if not student is String or student.is_empty() or checked.has(student):return false
  checked[student]=true
 event_id=id;eligible=checked;present=checked.duplicate();return true

func set_hand(host: bool,id: String,student: String,raised: bool) -> bool:
 if not host or id!=event_id or not present.has(student) or student==selected:return false
 if raised and student not in hands:hands.append(student)
 elif not raised:hands.erase(student)
 return true

func call_next(host: bool,id: String) -> String:
 if not host or id!=event_id or not selected.is_empty() or hands.is_empty():return ""
 selected=hands.pop_front();return selected

func call_student(host: bool,id: String,student: String) -> bool:
 if not host or id!=event_id or not selected.is_empty() or not present.has(student):return false
 hands.erase(student);selected=student;return true

func finish_turn(host: bool,id: String) -> bool:
 if not host or id!=event_id or selected.is_empty():return false
 selected="";return true

func disconnected(host: bool,student: String) -> bool:
 if not host or not present.has(student):return false
 hands.erase(student);present.erase(student)
 if selected==student:selected=""
 return true

func rejoined(host: bool,id: String,student: String) -> bool:
 if not host or id!=event_id or not eligible.has(student):return false
 present[student]=true;return true

func add_participant(host: bool,id: String,student: String) -> bool:
 if not host or id!=event_id or id.is_empty() or student.is_empty() or eligible.has(student) or eligible.size()>=MAX_STUDENTS:return false
 eligible[student]=true;present[student]=true;return true

func snapshot() -> Dictionary:
 return {"event_id":event_id,"hands":hands.duplicate(),"selected":selected}

func close(host: bool,id: String) -> bool:
 if not host or id!=event_id or id.is_empty():return false
 event_id="";eligible.clear();present.clear();hands.clear();selected="";return true
