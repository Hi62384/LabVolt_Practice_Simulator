extends RefCounted
## Host-owned bounded contributions for a classroom question.
const MAX_ENTRIES:=16
const MAX_TEXT:=160
var mode: String=""
var members:={}
var present:={}
var groups:={}
var entries: Array[Dictionary]=[]
var votes:={}
var explanations:={}
var serial:=0
var closed:=false
var task_kind:="general"
var group_labels: Array[String]=["A"]

func set_question(prompt: String) -> void:
 var value:=prompt.to_lower()
 task_kind="circuit" if "circuit" in value or "resistor" in value or "voltage" in value or "current" in value else ("math" if "equation" in value or "function" in value or "probability" in value or "graph" in value else "general")

func task(identity: String) -> String:
 if mode!="group" or not members.has(identity):return ""
 if members.size()==1:return "Solve the question and add a short explanation before submitting."
 var group:=str(groups.get(identity,""))
 if task_kind=="circuit":return "Calculate the circuit result together and note your method." if group in ["A","C"] else "Check the circuit assumptions and units; note any correction."
 if task_kind=="math":return "Solve the mathematical question together and note your method." if group in ["A","C"] else "Verify the result with another method or a counterexample."
 return "Work out a team answer and note your reasoning." if group in ["A","C"] else "Check the reasoning and note a challenge or improvement."

func begin(kind: String,identities: Array) -> bool:
 if kind not in ["board","group"] or identities.is_empty() or identities.size()>32 or not mode.is_empty():return false
 var ordered:=identities.duplicate();ordered.sort()
 group_labels.assign(["A"] if kind=="board" or ordered.size()==1 else (["A","B","C","D"] if ordered.size()>=7 else ["A","B"]))
 for i in ordered.size():
  var identity: Variant=ordered[i]
  if not identity is String or identity.is_empty() or members.has(identity):members.clear();return false
  members[identity]=true
  present[identity]=true
  groups[identity]=group_labels[i%group_labels.size()]
 mode=kind;return true

func add_member(identity: String) -> bool:
 if closed or identity.is_empty() or members.has(identity) or members.size()>=32:return false
 var counts:={}
 for label in group_labels:counts[label]=0
 for group in groups.values():counts[str(group)]=int(counts.get(str(group),0))+1
 var target:=group_labels[0]
 for label in group_labels:
  if int(counts[label])<int(counts[target]):target=label
 members[identity]=true;present[identity]=true;groups[identity]=target
 return true

func set_present(identity: String,active: bool) -> void:
 if not members.has(identity):return
 if active:present[identity]=true
 else:present.erase(identity)

func contribute(identity: String,text: Variant) -> String:
 if closed or not members.has(identity):return "not_participating"
 if not text is String:return "invalid"
 var value: String=text.strip_edges()
 if value.is_empty() or value.length()>MAX_TEXT or value.contains("\n") or value.contains("\r"):return "invalid"
 for entry in entries:
  if entry.author==identity and str(entry.get("kind","note"))=="note":return "already_submitted"
 if entries.size()>=MAX_ENTRIES:return "full"
 serial+=1
 entries.append({"id":serial,"author":identity,"group":groups[identity],"text":value})
 return "accepted"

func explain(identity: String,text: Variant) -> String:
 if mode!="group" or closed or not present.has(identity):return "denied"
 if not text is String:return "invalid"
 var value: String=text.strip_edges()
 if value.is_empty() or value.length()>MAX_TEXT or value.contains("\n") or value.contains("\r"):return "invalid"
 if explanations.has(identity):return "already_submitted"
 if entries.size()>=MAX_ENTRIES:return "full"
 var teammate_note:=false
 for entry in entries:
  if str(entry.group)==str(groups.get(identity,"")) and str(entry.author)!=identity:teammate_note=true;break
 if not teammate_note:return "no_teammate_note"
 serial+=1
 entries.append({"id":serial,"author":identity,"group":groups[identity],"text":value,"kind":"explanation"})
 explanations[identity]=true
 return "accepted"

func vote(identity: String,agree: Variant) -> String:
 if mode!="group" or closed or not present.has(identity):return "denied"
 if not agree is bool:return "invalid"
 var group:=str(groups[identity])
 if not entries.any(func(entry):return entry.group==group):return "no_proposal"
 votes[identity]=agree
 return "accepted"

func view(identity: String) -> Dictionary:
 var visible: Array=[]
 for entry in entries:
  if mode=="board" or groups.get(identity,"")==entry.group:
   visible.append({"id":entry.id,"group":entry.group,"text":entry.text,"kind":str(entry.get("kind","note"))})
 var submitted:=false
 for entry in entries:
  if entry.author==identity and str(entry.get("kind","note"))=="note":submitted=true;break
 var proposal: String=""
 var agree_count:=0;var disagree_count:=0
 if mode=="group" and members.has(identity):
  var group:=str(groups[identity])
  for entry in visible:
   if proposal.is_empty():proposal=str(entry.text)
  for voter in votes:
   if not present.has(voter) or str(groups.get(voter,""))!=group:continue
   if votes[voter]:agree_count+=1
   else:disagree_count+=1
 var teammate_note:=false
 for entry in entries:
  if str(entry.group)==str(groups.get(identity,"")) and str(entry.author)!=identity:teammate_note=true;break
 return {"mode":mode,"group":groups.get(identity,""),"task":task(identity),"entries":visible,"contributed":submitted,"can_contribute":members.has(identity) and present.has(identity) and not submitted and entries.size()<MAX_ENTRIES and not closed,"explained":explanations.has(identity),"can_explain":mode=="group" and present.has(identity) and teammate_note and not explanations.has(identity) and entries.size()<MAX_ENTRIES and not closed,"count":visible.size() if mode=="group" else entries.size(),"proposal":proposal,"agree":agree_count,"disagree":disagree_count,"vote":votes.get(identity) if present.has(identity) else null}

func finish() -> void:closed=true
