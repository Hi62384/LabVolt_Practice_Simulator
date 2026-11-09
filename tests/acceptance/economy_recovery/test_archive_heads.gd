extends SceneTree
const Ledger=preload("res://scripts/inventory_authority/ledger.gd")
const Profile=preload("res://scripts/electronics_profile.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures+=1;push_error("ARCHIVE_HEAD_FAIL "+label)
func run() -> void:
	var base:=OS.get_environment("LABVOLT_ECONOMY_RUN_ROOT").replace("\\","/").to_lower().trim_suffix("/")
	if base.is_empty() or not OS.get_user_data_dir().replace("\\","/").to_lower().begins_with(base+"/"):
		push_error("Isolated test profile required");quit(2);return
	var profile=Profile.new();profile.open("head-check")
	var ledger=Ledger.new()
	check(ledger.open("user://head-check")==OK,"fresh actual ledger")
	check(ledger.bind(1,"1".repeat(48),"5".repeat(64),profile.data).ok,"real profile bound")
	var earlier: Dictionary={}
	var earlier_bytes:=PackedByteArray()
	var earlier_file:=""
	for i in 70:
		check(ledger.transact(1,"head-%02d"%i,"buy",["r1000",1]).ok,"actual purchase "+str(i))
		if i==34:
			earlier=ledger.state.duplicate(true)
			earlier_file=ledger.receipt_history.blobs.root+"/"+str(earlier.receipt_archive.head)+".bin"
			earlier_bytes=FileAccess.get_file_as_bytes(earlier_file)
	check(ledger.state.receipt_archive.segments==1,"38 cold records share one bounded immutable head")
	check(ledger.account(1).receipts.size()==32,"32 active receipts")
	check(not earlier_bytes.is_empty() and FileAccess.get_file_as_bytes(earlier_file)==earlier_bytes,"earlier head bytes untouched")
	check(ledger.receipt_history.verify(earlier).ok,"earlier complete root remains valid")
	check(ledger.receipt_history.lookup_op(earlier,"1".repeat(48),"head-00").found,"earlier cold id retained")
	check(int(earlier.accounts["1".repeat(48)].profile.dollars)==65,"earlier balance remains historical65")
	check(int(ledger.account(1).profile.dollars)==30 and int(ledger.account(1).profile.inventory.r1000)==78,"actual70 debits and units")
	var head: Dictionary=ledger.receipt_history.blobs.read_segment(ledger.state.receipt_archive.head)
	check(head.ok and head.segment.records.size()==38,"all38 cold receipt records in head")
	var seen:={}
	if head.ok:
		for item in head.segment.records:
			check(not seen.has(item.id),"no duplicate cold id "+item.id);seen[item.id]=true
	for i in 70:
		var found: Dictionary=ledger.receipt_history.lookup_op(ledger.state,"1".repeat(48),"head-%02d"%i)
		check(found.ok and found.found,"all70 active/archive IDs "+str(i))
	var before: Dictionary=ledger.state.duplicate(true)
	check(ledger.transact(1,"head-00","buy",["r1000",1]).ok,"real oldest duplicate accepted")
	check(Profile.same(before,ledger.state),"duplicate cannot debit again")
	check(not ledger.transact(1,"head-00","buy",["r1000",2]).ok and Profile.same(before,ledger.state),"changed oldest id rejects without mutation")
	print(JSON.stringify({"suite":"archive_immutable_heads","checks":checks,"ok":failures==0,"scope":"actual immutable packing and historical root correctness; not latency or OS-crash proof"}))
	quit(1 if failures>0 else 0)
