extends SceneTree
# Requires sole-integrator hooks against CURRENT main; missing hooks fail, never skip.
const Ledger=preload("res://scripts/inventory_authority/ledger.gd")
const Store=preload("res://scripts/inventory_authority/store.gd")
const Profile=preload("res://scripts/electronics_profile.gd")
const Format=preload("res://scripts/inventory_authority/receipt_archive/format.gd")
var failed := false
var checks := 0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
 checks+=1
 if not ok:failed=true;push_error("ARCHIVE_INTEGRATION_FAIL "+label)
func seed_profile() -> Dictionary:
 var p=Profile.new();p.open("archive-integration-v3-seed");return p.data.duplicate(true)
func run() -> void:
 var base := OS.get_environment("LABVOLT_ECONOMY_RUN_ROOT").replace("\\","/").simplify_path().to_lower().trim_suffix("/")
 var actual := OS.get_user_data_dir().replace("\\","/").simplify_path().to_lower()
 if base.is_empty() or not base.is_absolute_path() or not actual.begins_with(base+"/"):
  push_error("Refusing non-isolated APPDATA");quit(2);return
 var path := "user://archive-integration-v3"
 if FileAccess.file_exists(path+".0") or FileAccess.file_exists(path+".1"):
  push_error("Fresh isolated profile required");quit(2);return
 var ledger=Ledger.new()
 if not ledger.has_method("receipt_delivery_hints"):
  push_error("MISSING_INTEGRATOR_HOOKS: archive is not accepted without current-main integration");quit(2);return
 check(ledger.open(path)==OK and ledger.state.schema==2,"current-main archive-aware ledger")
 check(ledger.bind(1,"1".repeat(48),"5".repeat(64),seed_profile()).ok,"bind actual source")
 check(ledger.bind(2,"2".repeat(48),"6".repeat(64),seed_profile()).ok,"bind actual receiver")
 for i in 40:check(ledger.transact(1,"buy-%02d"%i,"buy",["r1000",1]).ok,"real shop transaction")
 check(Format.bounded(ledger.state) and not ledger.account(1).receipts.has("buy-00"),"old operation cold, hot bounded")
 check(int(ledger.account(1).profile.dollars)==60 and int(ledger.account(1).profile.inventory.r1000)==48,"40 real independent debits/increments")
 var before: Dictionary=ledger.state.duplicate(true)
 check(ledger.transact(1,"buy-00","buy",["r1000",1]).ok,"cold op duplicate current snapshot contract")
 check(Profile.same(before,ledger.state),"cold duplicate no economic/revision mutation")
 check(not ledger.transact(1,"buy-00","buy",["r1000",2]).ok,"cold id changed payload rejected")
 check(Profile.same(before,ledger.state),"cold collision no mutation")
 var first := {}
 for i in 10:
  var offers := {1:{"r1000":1},2:{"r220":1}} if i%2==0 else {1:{"r220":1},2:{"r1000":1}}
  var result: Dictionary=ledger.exchange("trade-%02d"%i,[1,2],offers,{})
  check(result.ok,"real production two-owner exchange")
  if i==0:first=result.duplicate(true)
 check(not ledger.state.transactions.has("trade-00") and Format.bounded(ledger.state),"complete old trade moved cold")
 before=ledger.state.duplicate(true)
 var replay: Dictionary=ledger.exchange("trade-00",[1,2],{1:{"r1000":1},2:{"r220":1}},{})
 check(Profile.same(first,replay),"cold replay returns EXACT historical decision contract")
 check(Profile.same(before,ledger.state),"cold trade does not execute twice")
 check(not ledger.exchange("trade-00",[1,2],{1:{"r1000":2},2:{"r220":1}},{}).ok,"cold request proof rejects changed offer")
 check(Profile.same(before,ledger.state),"changed cold offer no mutation")
 var journal := {"trade-00":{"deliveries":{},"authoritative":true},"trade-01":{"deliveries":{"1".repeat(48):true,"forged":true},"authoritative":true},"trade-02":{"deliveries":{"1".repeat(48):"true","2".repeat(48):1},"authoritative":true},"trade-03":{"deliveries":{"1".repeat(48):true},"authoritative":false},"trade-04":"malformed"}
 check(ledger.call("receipt_delivery_hints",journal) and journal.size()==10 and journal.has("trade-00"),"delivery recovery includes cold decisions and existing bad hints")
 check(journal["trade-00"].deliveries.size()==2 and journal["trade-00"].deliveries.values()==[false,false],"empty existing hint repaired without fabricated ack")
 check(journal["trade-01"].deliveries.get("1".repeat(48))==true and journal["trade-01"].deliveries.get("2".repeat(48))==false and not journal["trade-01"].deliveries.has("forged"),"only valid authoritative owner ack preserved")
 for id in ["trade-02","trade-03","trade-04"]:check(journal[id].deliveries.size()==2 and journal[id].deliveries.values()==[false,false],"malformed/untrusted ack never promoted")
 # Explicit unit event exercises existing host reward path; no real grade is fabricated.
 check(ledger.award(1,"archive-unit-grade",100,0,false).earned==60,"existing host award")
 check(ledger.award(1,"archive-unit-grade",100,0,false).earned==0 and int(ledger.account(1).profile.dollars)==120,"existing reward id pays exactly once")
 var reopened=Ledger.new();check(reopened.open(path)==OK,"reopen integrated production ledger")
 check(reopened.bind(11,"1".repeat(48),"5".repeat(64),seed_profile()).ok,"rebind new transport peer")
 check(reopened.bind(22,"2".repeat(48),"6".repeat(64),seed_profile()).ok,"rebind receiver")
 before=reopened.state.duplicate(true)
 check(reopened.transact(11,"buy-00","buy",["r1000",1]).ok,"cold purchase survives restart")
 check(Profile.same(reopened.exchange("trade-00",[11,22],{11:{"r1000":1},22:{"r220":1}},{}),first),"stable authenticated identities survive cold restart")
 check(Profile.same(before,reopened.state),"restart duplicates unchanged")
 # Reconstruct supported old representation using ONLY complete real production receipts.
 var legacy: Dictionary=reopened.state.duplicate(true)
 legacy.schema=1;legacy.erase("receipt_archive");legacy.erase("receipt_v1_backup")
 var history=reopened.get("receipt_history")
 for i in 40:
  var id := "buy-%02d"%i
  var seen: Dictionary=history.lookup_op(reopened.state,"1".repeat(48),id)
  check(seen.ok and seen.found,"materialize known-v1 actual op receipt")
  legacy.accounts["1".repeat(48)].receipts[id]=seen.value
 for i in 10:
  var id := "trade-%02d"%i
  var seen: Dictionary=history.lookup_trade(reopened.state,id)
  check(seen.ok and seen.found,"materialize known-v1 complete trade")
  legacy.transactions[id]=seen.value
 legacy.transactions["trade-00"].erase("request") # Genuine pre-proof compatibility case; never fabricate proof.
 var legacy_store=Store.new()
 check(legacy_store.open(path+"-legacy")==OK and legacy_store.commit(legacy)==OK,"supported v1 production generation")
 var migrated=Ledger.new();check(migrated.open(path+"-legacy")==OK,"integrated v1 migration")
 check(migrated.bind(11,"1".repeat(48),"5".repeat(64),seed_profile()).ok and migrated.bind(22,"2".repeat(48),"6".repeat(64),seed_profile()).ok,"migrated identities")
 var migrated_before: Dictionary=migrated.state.duplicate(true)
 check(not migrated.exchange("trade-00",[11,22],{11:{"r1000":1},22:{"r220":1}},{}).ok,"legacy unproven trade stays seen and blocked from execution")
 check(Profile.same(migrated_before,migrated.state),"legacy proof failure never mutates any profile")
 # Real filesystem corruption in this exclusive test profile must block every economic path.
 var file := FileAccess.open(history.blobs.root+"/"+reopened.state.receipt_archive.head+".bin",FileAccess.WRITE)
 if file==null:check(false,"open owned corruption fixture");quit(1);return
 file.store_string("torn archive");file.flush();file.close()
 before=reopened.state.duplicate(true)
 check(not reopened.transact(11,"buy-00","buy",["r1000",1]).ok,"unreadable archive blocks hot/cold duplicate")
 check(not reopened.transact(11,"new-buy","buy",["r1000",1]).ok,"unreadable archive blocks unseen purchase")
 check(not reopened.exchange("new-trade",[11,22],{11:{"r1000":1},22:{}},{}).ok,"unreadable archive blocks new trade")
 check(not reopened.award(11,"new-unit-event",100,0,false).ok,"unreadable archive blocks new reward")
 check(Profile.same(before,reopened.state),"all balances inventory ids and profiles unchanged on corruption")
 print(JSON.stringify({"suite":"receipt_archive_integration_v3","ok":not failed,"checks":checks,"scope":"production local integration; no process crash/peers/soak"}))
 quit(1 if failed else 0)
