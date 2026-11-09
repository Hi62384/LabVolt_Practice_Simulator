extends SceneTree
# Actual production Ledger/Store and archive I/O. No mocked successful transaction.
const Ledger=preload("res://scripts/inventory_authority/ledger.gd")
const Store=preload("res://scripts/inventory_authority/store.gd")
const Profile=preload("res://scripts/electronics_profile.gd")
const Board=preload("res://scripts/breadboard_model.gd")
const Archive=preload("res://scripts/inventory_authority/receipt_archive/coordinator.gd")
const Format=preload("res://scripts/inventory_authority/receipt_archive/format.gd")
var failed := false
var checks := 0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
 checks+=1
 if not ok:failed=true;push_error("ARCHIVE_FAIL "+label)
func isolated() -> bool:
 var base := OS.get_environment("LABVOLT_ECONOMY_RUN_ROOT").replace("\\","/").simplify_path().to_lower().trim_suffix("/")
 var actual := OS.get_user_data_dir().replace("\\","/").simplify_path().to_lower()
 return not base.is_empty() and base.is_absolute_path() and actual.begins_with(base+"/")
func seed_profile() -> Dictionary:
 var p=Profile.new();p.open("archive-store-v3-seed")
 return p.data.duplicate(true)
func raw(path: String) -> PackedByteArray:
 var file := FileAccess.open(path,FileAccess.READ)
 if file==null:return PackedByteArray()
 var bytes := file.get_buffer(file.get_length());file.close();return bytes
func run() -> void:
 if not isolated():push_error("Refusing non-isolated APPDATA");quit(2);return
 var outside=Archive.new();outside.configure("res://../outside-user-data")
 check(not outside.healthy,"archive refuses directory scope outside engine user data")
 var path := "user://archive-store-v3"
 if FileAccess.file_exists(path+".0") or FileAccess.file_exists(path+".1") or FileAccess.file_exists(path+"-producer.0") or FileAccess.file_exists(path+"-producer.1"):
  push_error("Fresh isolated profile required");quit(2);return
 var producer=Ledger.new();check(producer.open(path+"-producer")==OK,"real producer ledger")
 check(producer.bind(1,"1".repeat(48),"5".repeat(64),seed_profile()).ok,"producer owner one")
 check(producer.bind(2,"2".repeat(48),"6".repeat(64),seed_profile()).ok,"producer owner two")
 var receipts := {}
 for i in 35:
  var id := "real-buy-%02d"%i
  check(producer.transact(1,id,"buy",["r1000",1]).ok,"real committed purchase "+id)
  receipts[id]=producer.account(1).receipts[id]
 check(producer.transact(1,"real-eeprom-buy","buy",["eeprom25",1]).ok,"real EEPROM purchase")
 receipts["real-eeprom-buy"]=producer.account(1).receipts["real-eeprom-buy"]
 var board := Board.empty();board.parts=[{"id":"nv","type":"eeprom25","a":"A1","b":"F1","pins":["A1","F1","A2","F2","A3","F3","A4","F4"]}]
 check(producer.capture_components(1,board,{"board/nv":{"memory":{"17":123,"32767":42},"status":140}})=="","production EEPROM nonvolatile capture, not electrical write evidence")
 var metadata: Dictionary=producer.account(1).profile.duplicate(true)
 metadata.programs={"board/cpu":{"firmware":"mode D0 out\nwrite D0 1\nhalt","run":true}}
 check(producer.transact(1,"real-program-metadata","metadata",[metadata]).ok,"production program metadata")
 receipts["real-program-metadata"]=producer.account(1).receipts["real-program-metadata"]
 check(producer.award(1,"archive-store-unit-grade",100,0,false).earned==60,"existing host award unit input")
 check(producer.exchange("real-trade",[1,2],{1:{"r1000":1},2:{"r220":1}},{}).ok,"real committed trade")
 var decision: Dictionary=producer.state.transactions["real-trade"].duplicate(true)
 if failed:quit(1);return
 # Reconstruct known-v1 representation solely from real successful production receipts.
 var legacy: Dictionary=producer.state.duplicate(true)
 legacy.schema=1;legacy.erase("receipt_archive");legacy.erase("receipt_v1_backup")
 legacy.accounts["1".repeat(48)].receipts=receipts.duplicate(true)
 # Exercise genuine pre-request-proof compatibility without inventing authentication.
 legacy.transactions["real-trade"].erase("request")
 var old_decision: Dictionary=legacy.transactions["real-trade"].duplicate(true)
 var store=Store.new();check(store.open(path)==OK and store.commit(legacy)==OK,"known-v1 production generation")
 var original := raw(path+".1")
 var staged=Archive.new()
 staged.checkpoint=func(phase: String,_filename: String):return phase!="archive_verified_before_ledger_commit"
 var prepared: Dictionary=staged.open_store(store)
 check(not prepared.ok and staged.last_error.contains("observer"),"real backup/archive writes then abort before publication")
 var forbidden=Archive.new();forbidden.configure(path)
 check(not forbidden.prepare(legacy).ok,"ordinary persist cannot bypass known-v1 backup gate")
 var before_commit=Store.new();check(before_commit.open(path)==OK,"reopen at archive-before-publication boundary")
 check(Profile.same(before_commit.value,legacy),"unreferenced archive cannot change old balances or decisions")
 # This is a publication-boundary object reopen, NOT an actual OS/process crash.
 var archive=Archive.new();var opened: Dictionary=archive.open_store(before_commit)
 check(opened.ok,"migrate known v1 through real atomic Store.commit")
 if not opened.ok:quit(1);return
 var migrated: Dictionary=opened.state
 check(migrated.schema==2 and Format.bounded(migrated),"new schema and bounded hot receipts")
 for owner in legacy.accounts:
  for key in legacy.accounts[owner]:
   if key!="receipts":check(Profile.same(migrated.accounts[owner][key],legacy.accounts[owner][key]),"unchanged account content "+key)
 for id in receipts:
  var lookup: Dictionary=archive.lookup_op(migrated,"1".repeat(48),id)
  check(lookup.ok and lookup.found and lookup.value==receipts[id],"all original op ids hot+cold "+id)
 var old: Dictionary=archive.lookup_trade(migrated,"real-trade")
 check(old.ok and old.found and Profile.same(old.value,old_decision) and not old.value.has("request"),"legacy decision preserved without manufactured proof")
 check(not migrated.transactions.has("real-trade"),"unproven legacy trade kept cold and seen")
 var first_lookup: Dictionary=archive.lookup_op(migrated,"1".repeat(48),"real-buy-00")
 var changed_digest := var_to_bytes(["buy",["r1000",2]]).hex_encode().sha256_text()
 check(first_lookup.ok and first_lookup.found and first_lookup.value!=changed_digest,"cold original digest cannot match changed request; core rejection integration remains separately required")
 var absent := {}
 check(archive.delivery_hints(migrated,absent) and absent.has("real-trade"),"missing journal hint reconstructed from actual complete decision")
 var journal := {"real-trade":{"deliveries":{},"authoritative":true},"unknown-hint":{"deliveries":{"1".repeat(48):true},"authoritative":true,"_archive_seen":true}}
 check(archive.delivery_hints(migrated,journal),"existing incomplete journal repaired")
 check(journal["real-trade"].deliveries.size()==2 and journal["real-trade"].deliveries.values()==[false,false],"empty hint does not fabricate a delivered owner")
 check(not journal["unknown-hint"]._archive_seen,"saved membership flag never proves a decision exists")
 journal["real-trade"]={"deliveries":{"1".repeat(48):true,"2".repeat(48):"true","alien":true},"authoritative":true}
 check(archive.delivery_hints(migrated,journal),"partial malformed hint normalized")
 check(journal["real-trade"].deliveries.get("1".repeat(48))==true and journal["real-trade"].deliveries.get("2".repeat(48))==false and journal["real-trade"].deliveries.size()==2,"preserve only exact boolean authenticated-owner hint bits")
 check(raw(archive.blobs.root+"/v1-"+Format.digest(original)+".bin")==original,"exact original generation backed up")
 var reopened=Store.new();check(reopened.open(path)==OK,"new generation reopen")
 check(Profile.same(reopened.value,migrated),"atomic new root references verified archive")
 var fresh=Archive.new();check(fresh.open_store(reopened).ok,"schema two restart idempotence")
 var missing := migrated.duplicate(true);missing.receipt_archive.head="f".repeat(64)
 var missing_reader=Archive.new();missing_reader.configure(path)
 check(not missing_reader.lookup_op(missing,"1".repeat(48),"never-issued").ok,"missing archive cannot mean unseen")
 # Unknown versions are never silently migrated or published.
 var future: Dictionary=legacy.duplicate(true);future.schema=99
 var future_store=Store.new();check(future_store.open(path+"-future")==OK and future_store.commit(future)==OK,"future-schema fixture")
 var future_reader=Archive.new();check(not future_reader.open_store(future_store).ok,"unknown ledger version fails closed")
 check(Profile.same(future_store.value,future),"unknown schema unchanged")
 var segment_path: String=archive.blobs.root+"/"+migrated.receipt_archive.head+".bin"
 var bytes := raw(segment_path);check(not bytes.is_empty(),"real archived bytes exist")
 if bytes.is_empty():quit(1);return
 var file := FileAccess.open(segment_path,FileAccess.WRITE)
 if file==null:check(false,"corruption fixture open");quit(1);return
 bytes[0]=int(bytes[0])^1;file.store_buffer(bytes);file.flush();file.close()
 var corrupt=Archive.new();corrupt.configure(path)
 check(not corrupt.lookup_op(migrated,"1".repeat(48),"real-buy-34").ok,"corrupt cold history blocks even a hot hit")
 var cold=Archive.new();cold.configure(path)
 check(not cold.lookup_op(migrated,"1".repeat(48),"never-issued").ok,"corrupt archive blocks unseen request")
 var after_corruption=Store.new();check(after_corruption.open(path)==OK and after_corruption.value.schema==2,"store still chooses committed new ledger")
 var reject=Archive.new();check(not reject.open_store(after_corruption).ok,"corrupt referenced archive never falls back to stale v1 economy")
 print(JSON.stringify({"suite":"receipt_archive_store_v3","ok":not failed,"checks":checks,"actual_process_crash_tested":false}))
 quit(1 if failed else 0)
