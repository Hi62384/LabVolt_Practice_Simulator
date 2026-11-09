extends SceneTree
const Ledger=preload("res://scripts/inventory_authority/ledger.gd")
const Profile=preload("res://scripts/electronics_profile.gd")
const Store=preload("res://scripts/inventory_authority/store.gd")
class ObservedStore:
	extends "res://scripts/inventory_authority/store.gd"
	# Observation-only wrapper. Actual disk commit and its Error come from super.
	# No fabricated success, alternate persistence, or changed economic mutation.
	var barrier:=""
	func pause_at(phase: String) -> void:
		print("ARCHIVE_CRASH_READY "+phase)
		OS.delay_msec(20000)
		push_error("CRASH_NOT_PERFORMED: ordinary persist barrier timed out")
	func commit(next: Dictionary) -> Error:
		if barrier=="archive_verified_before_ledger_commit":
			pause_at(barrier);return ERR_TIMEOUT
		var result: Error=super.commit(next)
		if result==OK and barrier=="ledger_committed":
			pause_at(barrier);return ERR_TIMEOUT
		return result
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures+=1;push_error("ARCHIVE_HEAD_CRASH_FAIL "+label)
func seed_profile() -> Dictionary:
	var p=Profile.new();p.open("head-crash-seed");return p.data.duplicate(true)
func run() -> void:
	var base:=OS.get_environment("LABVOLT_ECONOMY_RUN_ROOT").replace("\\","/").to_lower().trim_suffix("/")
	var args:=OS.get_cmdline_user_args()
	if base.is_empty() or not OS.get_user_data_dir().replace("\\","/").to_lower().begins_with(base+"/") or args.size()!=2 or args[0] not in ["prepare","recover"] or args[1] not in ["blob_flushed_before_rename","archive_verified_before_ledger_commit","ledger_committed"]:
		push_error("Explicit isolated action/phase required");quit(2);return
	var path:="user://head-crash-"+args[1]
	if args[0]=="recover":recover(path,args[1]);return
	if FileAccess.file_exists(path+".0") or FileAccess.file_exists(path+".1"):
		push_error("Fresh profile required");quit(2);return
	var ledger=Ledger.new();check(ledger.open(path)==OK,"actual fresh production ledger")
	check(ledger.bind(1,"1".repeat(48),"5".repeat(64),seed_profile()).ok,"real owner")
	for i in 35:check(ledger.transact(1,"pack-%02d"%i,"buy",["r1000",1]).ok,"real schema2 seed purchase")
	check(ledger.state.schema==2 and ledger.state.receipt_archive.segments==1,"committed schema2 existing partial head")
	var old: Dictionary=ledger.state.duplicate(true)
	var original: String=ledger.receipt_history.blobs.root+"/"+str(old.receipt_archive.head)+".bin"
	var old_bytes:=FileAccess.get_file_as_bytes(original)
	var info:=FileAccess.open(path+"-expected.bin",FileAccess.WRITE)
	if info==null:check(false,"owned expectation sidecar");quit(1);return
	info.store_var({"state":old,"bytes":old_bytes,"file":original});info.flush();info.close()
	var observed=ObservedStore.new();check(observed.open(path)==OK,"observer reopens real production generations")
	observed.barrier=args[1] if args[1]!="blob_flushed_before_rename" else ""
	ledger.store=observed
	ledger.receipt_history.blobs.checkpoint=func(phase: String,filename: String):
		if phase==args[1] and phase=="blob_flushed_before_rename" and filename!=str(old.receipt_archive.head)+".bin":
			print("ARCHIVE_CRASH_READY "+phase)
			OS.delay_msec(20000)
			push_error("CRASH_NOT_PERFORMED: replacement head barrier timed out")
			return false
		return true
	if failures>0:quit(1);return
	var result: Dictionary=ledger.transact(1,"pack-next","buy",["r1000",1])
	push_error("CRASH_NOT_PERFORMED: operation returned "+str(result.ok));quit(3)
func recover(path: String,phase: String) -> void:
	var file:=FileAccess.open(path+"-expected.bin",FileAccess.READ)
	if file==null:check(false,"expectation sidecar exists");quit(1);return
	var expected: Dictionary=file.get_var(false);file.close()
	var ledger=Ledger.new();check(ledger.open(path)==OK,"actual recovery opens verified root")
	check(ledger.bind(11,"1".repeat(48),"5".repeat(64),seed_profile()).ok,"real rebound owner")
	var dollars:=64 if phase=="ledger_committed" else 65
	check(int(ledger.account(11).profile.dollars)==dollars,"old or newly committed economic state at exact barrier")
	check(FileAccess.get_file_as_bytes(expected.file)==expected.bytes,"old immutable head bytes retained")
	check(ledger.receipt_history.verify(expected.state).ok,"old complete root still verifies")
	var prior: Dictionary=ledger.state.duplicate(true)
	check(ledger.transact(11,"pack-next","buy",["r1000",1]).ok,"real uncommitted retry or committed replay")
	if phase=="ledger_committed":check(Profile.same(prior,ledger.state),"committed replay cannot mutate again")
	check(int(ledger.account(11).profile.dollars)==64 and int(ledger.account(11).profile.inventory.r1000)==44,"exactly36 purchases after recovery")
	check(ledger.state.receipt_archive.segments==1,"replacement head remains one segment")
	var head: Dictionary=ledger.receipt_history.blobs.read_segment(ledger.state.receipt_archive.head)
	check(head.ok and head.segment.records.size()==4,"coalesced head retains all4cold records")
	var seen:={}
	if head.ok:
		for item in head.segment.records:
			check(not seen.has(item.id),"unique cold receipt");seen[item.id]=true
	for i in 35:
		var found: Dictionary=ledger.receipt_history.lookup_op(ledger.state,"1".repeat(48),"pack-%02d"%i)
		check(found.ok and found.found,"all35 original IDs survive")
	var next: Dictionary=ledger.receipt_history.lookup_op(ledger.state,"1".repeat(48),"pack-next")
	check(next.ok and next.found,"new ID retained")
	print(JSON.stringify({"suite":"archive_head_crash","phase":phase,"ok":failures==0,"checks":checks,"existing_schema2_head":true,"observation_wrapper_delegates_real_store":true}))
	quit(1 if failures>0 else 0)
