extends SceneTree
## Native local retrieval/persistence checks. No provider or generated dialogue.
const Life=preload("res://scripts/campus/academics/character_life_memory.gd")
var failures: Array[String]=[]
var checks:=0
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize() -> void:
	var records: Dictionary={}
	for i in 2000:
		var id:="experience."+str(i)
		records[id]={"id":id,"topic":id,"detail":"An ordinary stored experience numbered "+str(i)+".","value":str(i),"kind":"historical","provenance":"improvised_fiction","at":100,"history":[]}
	var fact:={"topic":"craft.first_instrument","detail":"My first instrument was a battered trumpet.","value":"trumpet","kind":"historical","entities":["trumpet"],"aliases":["horn","brass instrument"],"chronology":"At age twelve"}
	var accepted:=Life.validate(fact,fact.detail,records)
	check(accepted.ok,"expandable life experience validates")
	Life.apply(records,accepted)
	check(Life.retrieve(records,"What was your first horn?",[],8,"host-a").any(func(row):return row.value=="trumpet"),"generated concept aliases use the same local index")
	var recent:=[{"student":"Tell me about your first instrument.","teacher":"A battered trumpet."}]
	check(Life.retrieve(records,"When was that?",recent,8,"host-a").any(func(row):return row.chronology=="At age twelve"),"short chronological follow-up resolves the preceding subject")
	var started:=Time.get_ticks_usec()
	for i in 100:Life.retrieve(records,"What was your first horn?",[],8,"host-a")
	var retrieval_ms:=float(Time.get_ticks_usec()-started)/100000.0
	var other:=records.duplicate(true)
	other["craft.first_instrument"].value="trombone";other["craft.first_instrument"].detail="My first horn was a trombone."
	check(Life.retrieve(other,"What was your first horn?",[],8,"host-b")[0].value=="trombone","different host cache never supplies the earlier host's record text")
	check(Life.retrieve(records,"What was your first horn?",[],8,"host-a")[0].value=="trumpet","alternating host retrieval preserves individual history")
	records["craft.first_instrument"].aliases.append("orchestra")
	check(Life.retrieve(records,"orchestra",[],8,"host-a")[0].value=="trumpet","material memory changes invalidate token postings")
	var preference:={"topic":"food.favorite","detail":"My favourite food is noodles.","value":"noodles","kind":"preference"}
	var preferences: Dictionary={}
	Life.apply(preferences,Life.validate(preference,preference.detail,preferences))
	var update:={"topic":"food.favorite","detail":"My favourite food is dumplings now.","value":"dumplings","kind":"preference","revision":"update","reason":"I got tired of eating the same lunch."}
	accepted=Life.validate(update,update.detail+" "+update.reason,preferences)
	Life.apply(preferences,accepted)
	check(Life.valid_snapshot({"character":preferences}),"complete current record and chronological prior version pass disk validation")
	var corrupted:=preferences.duplicate(true);corrupted["food.favorite"].history[0].at="yesterday"
	check(not Life.valid_snapshot({"character":corrupted}),"corrupt historical metadata cannot survive snapshot validation")
	var changed:={"topic":"craft.first_instrument","detail":"My first instrument was a violin.","value":"violin","kind":"historical"}
	check(not Life.validate(changed,changed.detail,records).ok,"permanent historical fact cannot be silently replaced")
	print("CHARACTER_LIFE_LEDGER ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," records=",records.size()," indexed_lookup_average_ms=",retrieval_ms," serialized_bytes=",JSON.stringify(records).to_utf8_buffer().size()," provider_requests=0")
	quit(0 if failures.is_empty() else 1)
