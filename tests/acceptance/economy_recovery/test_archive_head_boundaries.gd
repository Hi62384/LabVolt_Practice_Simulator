extends SceneTree
const Ledger=preload("res://scripts/inventory_authority/ledger.gd")
const Profile=preload("res://scripts/electronics_profile.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures+=1;push_error("ARCHIVE_HEAD_BOUNDARY_FAIL "+label)
func run() -> void:
	var base:=OS.get_environment("LABVOLT_ECONOMY_RUN_ROOT").replace("\\","/").to_lower().trim_suffix("/")
	if base.is_empty() or not OS.get_user_data_dir().replace("\\","/").to_lower().begins_with(base+"/"):
		push_error("Explicit isolated profile required");quit(2);return
	var profile=Profile.new();profile.open("head-boundaries")
	profile.data.dollars=1000 # Declared test starting credit, not a gameplay reward.
	var ledger=Ledger.new();check(ledger.open("user://head-boundaries")==OK,"actual ledger open")
	check(ledger.bind(1,"1".repeat(48),"5".repeat(64),profile.data).ok,"real credential bound")
	var expected:={}
	var old: Dictionary={}
	var old_file:=""
	var old_bytes:=PackedByteArray()
	var full_head:=""
	var full_bytes:=PackedByteArray()
	for i in 97:
		var id:="bound-%02d"%i
		var result: Dictionary=ledger.transact(1,id,"buy",["r1000",1])
		check(result.ok,"real purchase "+id)
		if not result.ok:quit(1);return
		expected[id]=ledger.account(1).receipts[id]
		if i==34:
			old=ledger.state.duplicate(true)
			old_file=ledger.receipt_history.blobs.root+"/"+str(old.receipt_archive.head)+".bin"
			old_bytes=FileAccess.get_file_as_bytes(old_file)
		if i==95:
			full_head=ledger.state.receipt_archive.head
			var head: Dictionary=ledger.receipt_history.blobs.read_segment(full_head)
			check(ledger.state.receipt_archive.segments==1 and head.ok and head.segment.records.size()==64,"exact64records fit one head")
			full_bytes=FileAccess.get_file_as_bytes(ledger.receipt_history.blobs.root+"/"+full_head+".bin")
	check(ledger.state.receipt_archive.segments==2 and ledger.account(1).receipts.size()==32,"65coldrecords append second bounded segment")
	var top: Dictionary=ledger.receipt_history.blobs.read_segment(ledger.state.receipt_archive.head)
	check(top.ok and top.segment.records.size()==1 and top.segment.previous==full_head,"new65th record links original full64head")
	check(FileAccess.get_file_as_bytes(ledger.receipt_history.blobs.root+"/"+full_head+".bin")==full_bytes,"full64head remains byte identical")
	check(FileAccess.get_file_as_bytes(old_file)==old_bytes and ledger.receipt_history.verify(old).ok,"earlier partial root remains complete and byte identical")
	check(int(old.accounts["1".repeat(48)].profile.dollars)==965 and int(ledger.account(1).profile.dollars)==903 and int(ledger.account(1).profile.inventory.r1000)==105,"actual97debits/units and historical35 balance")
	var hash: String=ledger.state.receipt_archive.head
	var seen:={}
	for index in 2:
		var found: Dictionary=ledger.receipt_history.blobs.read_segment(hash)
		check(found.ok,"verified segment "+str(index))
		if not found.ok:quit(1);return
		check(found.segment.records.size()<=64 and var_to_bytes(found.segment).size()<=8388608,"count/byte bound respected")
		for item in found.segment.records:
			var exact: Dictionary={"kind":"op","owner":"1".repeat(48),"id":item.id,"value":expected.get(item.id,"")}
			check(expected.has(item.id) and not seen.has(item.id) and Profile.same(item,exact),"full cold record exact and unique "+item.id)
			seen[item.id]=true
		hash=found.segment.previous
	check(hash=="" and seen.size()==65,"all65coldrecords exactly once")
	for id in expected:
		var found: Dictionary=ledger.receipt_history.lookup_op(ledger.state,"1".repeat(48),id)
		check(found.ok and found.found and found.value==expected[id],"all97full op digests exact")
	print(JSON.stringify({"suite":"archive_head_boundaries","ok":failures==0,"checks":checks,"records":97,"cold_records":65,"segments":2}))
	quit(1 if failures>0 else 0)
