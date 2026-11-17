extends SceneTree
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
const Dialogue=preload("res://scripts/campus/academics/teacher_dialogue.gd")
func _initialize() -> void:
	var brain=Brain.new()
	var first: String="a".repeat(48);var second: String="b".repeat(48)
	for i in 4:brain.remember("mr_stone",first,"help",100000+i)
	for i in 3:brain.remember("mr_stone",second,"disruption",100000+i)
	var ok: bool=brain.relationship("mr_stone",first).positive==4 and brain.relationship("mr_stone",first).disruptions==0
	ok=ok and brain.relationship("mr_stone",second).disruptions==3 and brain.relationship("mr_apple",second).familiarity==0
	ok=ok and brain.save_memory()==OK
	var restored=Brain.new();restored.load_memory()
	ok=ok and restored.relationship("mr_stone",first).positive==4 and restored.relationship("mr_stone",second).disruptions==3
	restored.remember("mr_stone",second,"conversation",100003+2*86400)
	ok=ok and restored.relationship("mr_stone",second).disruptions==1
	ok=ok and restored.save_memory()==OK
	var updated=Brain.new();updated.load_memory()
	ok=ok and updated.relationship("mr_stone",second).disruptions==1
	var frequent=Brain.new()
	frequent.remember("jeff",first,"disruption",100000)
	frequent.remember("jeff",first,"disruption",100001)
	for hour in range(1,49):frequent.remember("jeff",first,"conversation",100001+hour*3600)
	ok=ok and frequent.relationship("jeff",first).disruptions==0
	frequent.remember("jeff",first,"disruption",100001+49*3600)
	frequent.remember("jeff",first,"conversation",100001+72*3600)
	ok=ok and frequent.relationship("jeff",first).disruptions==1
	frequent.remember("jeff",first,"conversation",100001+73*3600)
	ok=ok and frequent.relationship("jeff",first).disruptions==0
	var legacy:=FileAccess.open(Brain.MEMORY_PATH,FileAccess.WRITE)
	legacy.store_string(JSON.stringify({"version":1,"relationships":{"jeff:"+first:{"familiarity":3,"positive":1,"disruptions":2,"last_seen":100000}}}));legacy.close()
	var migrated=Brain.new();migrated.load_memory()
	for hour in range(1,49):migrated.remember("jeff",first,"conversation",100000+hour*3600)
	ok=ok and migrated.relationship("jeff",first).disruptions==0 and migrated.relationship("jeff",first).positive==1
	var text:=Dialogue.respond("mr_stone","help",{"relationship":restored.relationship("mr_stone",first)},0)
	ok=ok and text.contains("appreciate") and not str(restored.relationships).contains("private contents")
	var backup_seed=Brain.new()
	backup_seed.remember("bill_nye",first,"help",300000)
	ok=ok and backup_seed.save_memory()==OK
	backup_seed.remember("bill_nye",first,"help",300001)
	ok=ok and backup_seed.save_memory()==OK
	var damaged:=FileAccess.open(Brain.MEMORY_PATH,FileAccess.WRITE)
	damaged.store_string("{broken json");damaged.close()
	var recovered=Brain.new();recovered.load_memory()
	ok=ok and recovered.relationship("bill_nye",first).positive==1 and recovered.memory_dirty
	recovered.remember("bill_nye",first,"help",300002)
	ok=ok and recovered.save_memory()==OK
	var reloaded=Brain.new();reloaded.load_memory()
	ok=ok and reloaded.relationship("bill_nye",first).positive==2
	print("TEACHER_RELATIONSHIPS ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
