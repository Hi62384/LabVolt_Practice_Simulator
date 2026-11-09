extends SceneTree
# A root-owned Job must actually terminate this engine at the barrier.
# Object reopen and observer timeout are NEVER recorded as successful process crash.
const Ledger=preload("res://scripts/inventory_authority/ledger.gd")
const Store=preload("res://scripts/inventory_authority/store.gd")
const Profile=preload("res://scripts/electronics_profile.gd")
const Archive=preload("res://scripts/inventory_authority/receipt_archive/coordinator.gd")
const Format=preload("res://scripts/inventory_authority/receipt_archive/format.gd")
const PHASES := ["blob_flushed_before_rename","archive_verified_before_ledger_commit","ledger_committed"]
var failed := false
var checks := 0
var watchdog := false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
 checks+=1
 if not ok:failed=true;push_error("ARCHIVE_CRASH_FAIL "+label)
func seed_profile() -> Dictionary:
 var p=Profile.new();p.open("archive-crash-v3-seed");return p.data.duplicate(true)
func raw(path: String) -> PackedByteArray:
 var file := FileAccess.open(path,FileAccess.READ)
 if file==null:return PackedByteArray()
 var bytes := file.get_buffer(file.get_length());file.close();return bytes
func run() -> void:
 var base := OS.get_environment("LABVOLT_ECONOMY_RUN_ROOT").replace("\\","/").simplify_path().to_lower().trim_suffix("/")
 var actual := OS.get_user_data_dir().replace("\\","/").simplify_path().to_lower()
 var args := OS.get_cmdline_user_args()
 if base.is_empty() or not base.is_absolute_path() or not actual.begins_with(base+"/") or args.size()!=2 or args[0] not in ["prepare","recover"] or args[1] not in PHASES:
  push_error("Explicit isolated root/action/crash phase required");quit(2);return
 var path := "user://archive-crash-v3-"+args[1]
 if args[0]=="recover":recover(path,args[1]);return
 if FileAccess.file_exists(path+".0") or FileAccess.file_exists(path+".1") or FileAccess.file_exists(path+"-producer.0") or FileAccess.file_exists(path+"-producer.1"):
  push_error("Fresh test profile required");quit(2);return
 var producer=Ledger.new();check(producer.open(path+"-producer")==OK,"real producer open")
 check(producer.bind(1,"1".repeat(48),"5".repeat(64),seed_profile()).ok,"real owner")
 var receipts := {}
 for i in 35:
  var id := "crash-buy-%02d"%i
  check(producer.transact(1,id,"buy",["r1000",1]).ok,"real durable producer transaction")
  receipts[id]=producer.account(1).receipts[id]
 if failed:quit(1);return
 var old: Dictionary=producer.state.duplicate(true)
 old.schema=1;old.erase("receipt_archive");old.erase("receipt_v1_backup")
 old.accounts["1".repeat(48)].receipts=receipts
 var store=Store.new();check(store.open(path)==OK and store.commit(old)==OK,"known-v1 durable fixture")
 var archive=Archive.new()
 archive.checkpoint=func(phase: String,filename: String):
  if phase!=args[1] or (phase=="blob_flushed_before_rename" and filename.begins_with("v1-")):return true
  print("ARCHIVE_CRASH_READY "+phase)
  # Abort-only observation: never returns success if root fails to kill the actual Job.
  OS.delay_msec(20000)
  watchdog=true
  push_error("CRASH_NOT_PERFORMED: observation barrier timed out")
  return false
 var result: Dictionary=archive.open_store(store)
 # Any normal return means external process crash acceptance was NOT performed.
 push_error("CRASH_NOT_PERFORMED: migration returned normally; ok="+str(result.ok)+" watchdog="+str(watchdog))
 quit(3)
func recover(path: String,phase: String) -> void:
 var store=Store.new();check(store.open(path)==OK,"actual post-termination Store.open")
 if failed:quit(1);return
 check(store.value.schema==(2 if phase=="ledger_committed" else 1),"old/new committed generation at exact barrier")
 var original := raw(path+".1")
 check(not original.is_empty(),"original known-v1 generation still available")
 var archive=Archive.new();var opened: Dictionary=archive.open_store(store)
 check(opened.ok,"restart completes supported migration or reopens published v2")
 if not opened.ok:quit(1);return
 check(raw(archive.blobs.root+"/v1-"+Format.digest(original)+".bin")==original,"byte-for-byte v1 backup survives termination")
 var state: Dictionary=opened.state
 check(Format.bounded(state),"hot count and byte bounds survive recovery")
 check(int(state.accounts["1".repeat(48)].profile.dollars)==65 and int(state.accounts["1".repeat(48)].profile.inventory.r1000)==43,"exact money and owned units after actual termination")
 for i in 35:
  var seen: Dictionary=archive.lookup_op(state,"1".repeat(48),"crash-buy-%02d"%i)
  check(seen.ok and seen.found,"all actual operation ids retained across termination")
 print(JSON.stringify({"suite":"receipt_archive_crash_v3","phase":phase,"ok":not failed,"checks":checks,"external_owned_job_kill_evidence_required":true}))
 quit(1 if failed else 0)
