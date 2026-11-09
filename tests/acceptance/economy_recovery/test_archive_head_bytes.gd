extends SceneTree
# Required correctness of real byte bounds and real archive-write rollback; not a benchmark.
const Ledger=preload("res://scripts/inventory_authority/ledger.gd")
const Profile=preload("res://scripts/electronics_profile.gd")
const Format=preload("res://scripts/inventory_authority/receipt_archive/format.gd")
var failed := false
var checks := 0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
 checks+=1
 if not ok:failed=true;push_error("ARCHIVE_LIMIT_FAIL "+label)
func seed_profile() -> Dictionary:
 var p=Profile.new();p.open("archive-limits-v3-seed");return p.data.duplicate(true)
func run() -> void:
 var base := OS.get_environment("LABVOLT_ECONOMY_RUN_ROOT").replace("\\","/").simplify_path().to_lower().trim_suffix("/")
 var actual := OS.get_user_data_dir().replace("\\","/").simplify_path().to_lower()
 if base.is_empty() or not base.is_absolute_path() or not actual.begins_with(base+"/"):
  push_error("Refusing non-isolated APPDATA");quit(2);return
 var path := "user://archive-limits-v3"
 for suffix in [".0",".1","-bytes.0","-bytes.1"]:
  if FileAccess.file_exists(path+suffix):push_error("Fresh isolated profile required");quit(2);return
 var ledger=Ledger.new()
 if not ledger.has_method("receipt_delivery_hints"):
  push_error("MISSING_INTEGRATOR_HOOKS");quit(2);return
 check(ledger.open(path)==OK and ledger.bind(1,"1".repeat(48),"5".repeat(64),seed_profile()).ok,"real ledger/owner")
 # Deliberate file blocks only this fresh test profile's future archive directory.
 var file := FileAccess.open(path+".receipts",FileAccess.WRITE)
 if file==null:check(false,"owned blocking file fixture");quit(1);return
 file.store_string("owned non-history obstruction fixture");file.close()
 for i in 32:check(ledger.transact(1,"op-%02d"%i,"buy",["r1000",1]).ok,"real count-bound purchase")
 var before: Dictionary=ledger.state.duplicate(true)
 check(not ledger.transact(1,"op-32","buy",["r1000",1]).ok,"real archive mkdir/write failure rejects transaction")
 check(Profile.same(before,ledger.state),"archive write failure no receipt/balance/revision publication")
 check(int(ledger.account(1).profile.dollars)==68 and int(ledger.account(1).profile.inventory.r1000)==40,"exact 32 purchase baseline")
 check(DirAccess.rename_absolute(path+".receipts",path+".fixture-retained")==OK,"preserve obstruction bytes while repairing fixture")
 var reopened=Ledger.new();check(reopened.open(path)==OK,"reopen unmodified valid committed root")
 check(reopened.bind(11,"1".repeat(48),"5".repeat(64),seed_profile()).ok,"rebind authentic owner")
 check(reopened.transact(11,"op-32","buy",["r1000",1]).ok,"failed id retries after real archive repair")
 check(int(reopened.account(11).profile.dollars)==67 and int(reopened.account(11).profile.inventory.r1000)==41,"retry applied exactly once")
 before=reopened.state.duplicate(true)
 check(reopened.transact(11,"op-00","buy",["r1000",1]).ok,"first receipt moved cold and still seen")
 check(Profile.same(before,reopened.state),"cold replay after write repair unchanged")
 byte_bounds(path+"-bytes")
 print(JSON.stringify({"suite":"receipt_archive_limits_v3","ok":not failed,"checks":checks,"scope":"real byte-bound/write-failure correctness; not performance or soak"}))
 quit(1 if failed else 0)
func byte_bounds(path: String) -> void:
 var ledger=Ledger.new();check(ledger.open(path)==OK,"byte fixture real ledger")
 for peer in [1,2]:
  check(ledger.bind(peer,str(peer).repeat(48),str(peer+4).repeat(64),seed_profile()).ok,"byte fixture owner")
  var incoming: Dictionary=ledger.account(peer).profile.duplicate(true)
  incoming.notebook="N".repeat(650000)
  check(ledger.transact(peer,"notebook","metadata",[incoming]).ok,"large valid production notebook")
 if failed:return
 var first := {}
 var expected := {}
 for i in 10:
  var offers := {1:{"r1000":1},2:{"r220":1}} if i%2==0 else {1:{"r220":1},2:{"r1000":1}}
  var result: Dictionary=ledger.exchange("byte-trade-%d"%i,[1,2],offers,{})
  check(result.ok,"real complete profile trade decision")
  if i==0:first=result.duplicate(true)
  var saved: Dictionary=ledger.receipt_history.lookup_trade(ledger.state,"byte-trade-%d"%i)
  check(saved.ok and saved.found,"complete real decision retained")
  if saved.ok and saved.found:expected["byte-trade-%d"%i]=saved.value.duplicate(true)
 check(ledger.state.transactions.size()<10,"byte bound evicts before count limit eight")
 check(Format.hot_size(ledger.state)<=Format.HOT_BYTES and Format.bounded(ledger.state),"actual serialized hot byte/count limits")
 var before: Dictionary=ledger.state.duplicate(true)
 check(Profile.same(ledger.exchange("byte-trade-0",[1,2],{1:{"r1000":1},2:{"r220":1}},{}),first),"large cold historical decision replay exact")
 check(Profile.same(before,ledger.state),"large replay no economic mutation")
 for peer in [1,2]:check(ledger.account(peer).profile.notebook=="N".repeat(650000),"notebook bytes retained")

 check(ledger.state.receipt_archive.segments>=2,"8MiB merge overflow appends bounded segment")
 var hash: String=ledger.state.receipt_archive.head
 var seen := {}
 for index in int(ledger.state.receipt_archive.segments):
  var found: Dictionary=ledger.receipt_history.blobs.read_segment(hash)
  check(found.ok,"actual byte-bound archive segment verified")
  if not found.ok:return
  check(var_to_bytes(found.segment).size()<=8388608,"every actual segment within8MiB")
  for item in found.segment.records:
   check(item.kind=="trade" and not seen.has(item.id) and expected.has(item.id) and Profile.same(item.value,expected[item.id]),"full cold decision including request/profile preserved")
   seen[item.id]=true
  hash=found.segment.previous
 check(hash=="" and seen.size()==9,"all9 cold full decisions exactly once")
 for id in expected:
  var found: Dictionary=ledger.receipt_history.lookup_trade(ledger.state,id)
  check(found.ok and found.found and Profile.same(found.value,expected[id]),"all10 full hot/cold decisions exact")
