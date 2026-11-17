extends RefCounted
## Host-released, cumulative board state for ordinary offline lectures.
const MAX_HISTORY:=4
const MAX_TITLE:=54
const MAX_FORMULA:=100

static func at(teaching: Dictionary,title: String,elapsed: float,duration: float) -> Dictionary:
	var stages: Array=teaching.get("stages",[])
	if stages.is_empty():return {"title":title,"text":str(teaching.get("worked",teaching.get("equipment_text",""))).left(900),"index":0,"count":1,"board_history":[]}
	var remaining:=maxf(0.0,elapsed)
	var index:=0
	for i in stages.size():
		var stage: Dictionary=stages[i]
		remaining-=maxf(.01,float(stage.get("duration_seconds",stage.get("duration",duration/stages.size()))))
		if remaining<0.0 or i==stages.size()-1:index=i;break
	var current: Dictionary=stages[index].duplicate(true)
	current.index=index;current.count=stages.size()
	var history: Array[Dictionary]=[]
	for i in range(maxi(0,index-MAX_HISTORY),index):
		var source: Dictionary=stages[i]
		var entry:={"title":str(source.get("title","Step %d"%(i+1))).left(MAX_TITLE)}
		var formula:=str(source.get("formulas",""))
		if not formula.is_empty():entry.formula=formula.left(MAX_FORMULA)
		history.append(entry)
	current.board_history=history
	return current
