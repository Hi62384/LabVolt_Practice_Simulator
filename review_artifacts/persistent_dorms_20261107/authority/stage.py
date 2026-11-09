from pathlib import Path
import hashlib,json,difflib
ROOT=Path(__file__).resolve().parents[3]
PACK=Path(__file__).resolve().parent
OUT=PACK/'candidate'
manifest={}
def stage(path, transform):
    source=ROOT/path
    before=source.read_text(encoding='utf-8-sig') if source.exists() else ''
    after=transform(before)
    target=OUT/path;target.parent.mkdir(parents=True,exist_ok=True);target.write_text(after,encoding='utf-8',newline='\n')
    pre=PACK/'preimages'/path;pre.parent.mkdir(parents=True,exist_ok=True);pre.write_text(before,encoding='utf-8',newline='\n')
    manifest[path]={'preimage_sha256':hashlib.sha256(source.read_bytes()).hexdigest() if source.exists() else None,'candidate_sha256':hashlib.sha256(target.read_bytes()).hexdigest()}
    return after
def replace(text,old,new):
    assert text.count(old)==1,(old[:100],text.count(old))
    return text.replace(old,new)
def helper(_):return (PACK/'persistent_dorm.gd').read_text(encoding='utf-8-sig')
stage('scripts/campus/dorms/authority/persistent_dorm.gd',helper)
def ledger(t):
    t=replace(t,'extends RefCounted\n','extends RefCounted\nconst Dorm=preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")\n')
    t=replace(t,'\tbindings[peer]=identity\n','\tvar migration: Dictionary=Dorm.migrate(state.accounts[identity].profile,identity)\n\tif not migration.ok:return failure(migration.error)\n\tif migration.changed:\n\t\tvar next := state.duplicate(true)\n\t\tnext.accounts[identity].profile=migration.profile;next.accounts[identity].revision+=1\n\t\tif not persist(next):return failure("Dorm enrollment save failed")\n\tbindings[peer]=identity\n')
    t=replace(t,'\tvar imported := initial.duplicate(true);imported.erase("authority_credentials")','\tvar imported := initial.duplicate(true);imported.erase("authority_credentials")\n\tvar migrated: Dictionary=Dorm.migrate(imported,identity)\n\tif not migrated.ok:return failure(migrated.error)\n\timported=migrated.profile')
    t=replace(t,'-int(a.get("deployment",{}).get("counts",{}).get(type,0))','-int(a.get("deployment",{}).get("counts",{}).get(type,0))-int(a.get("profile",{}).get("dorm",{}).get("storage",{}).get(type,0))')
    t=replace(t,'p.craft_reservations=func():return a.deployment','p.craft_reservations=func():return {"counts":Dorm.reserved(a.profile,a.deployment),"instance_ids":a.deployment.get("instance_ids",[])+a.profile.get("dorm",{}).get("instances",[])}')
    t=replace(t,'\tmatch op:\n','\tmatch op:\n\t\t"dorm":\n\t\t\tif args.size()!=1 or not args[0] is Dictionary:return failure("Invalid dorm intent")\n\t\t\tvar result: Dictionary=Dorm.apply_intent(p.data,str(bindings[peer]),args[0],a.deployment)\n\t\t\tif not result.ok:return failure(result.error)\n\t\t\tp.data=result.profile;message="Dorm saved"\n')
    t=replace(t,'\tfor type in a.deployment.get("counts",{}):\n\t\tif int(p.data.inventory.get(type,0))<int(a.deployment.counts[type]):return failure("Recall deployed components first")','\tvar reservations: Dictionary=Dorm.reserved(p.data,a.deployment)\n\tfor type in reservations:\n\t\tif int(p.data.inventory.get(type,0))<int(reservations[type]):return failure("Recall deployed or stored components first")')
    t=replace(t,'\tvar next := state.duplicate(true)\n\tnext.accounts[bindings[peer]].deployment={"slot":slot', '\tfor type in counts:\n\t\tif int(counts[type])+int(account(peer).profile.get("dorm",{}).get("storage",{}).get(type,0))>int(account(peer).profile.inventory.get(type,0)):return "Retrieve stored components first"\n\tfor instance in design.get("instance_ids",{}).values():\n\t\tif instance in account(peer).profile.get("dorm",{}).get("instances",[]):return "Retrieve stored instance first"\n\tvar next := state.duplicate(true)\n\tnext.accounts[bindings[peer]].deployment={"slot":slot')
    t=replace(t,'var excluded: Array=source.deployment.get("instance_ids",[])','var excluded: Array=source.deployment.get("instance_ids",[]).duplicate();excluded.append_array(source.profile.get("dorm",{}).get("instances",[]))')
    t=replace(t,'var generic := int(source.profile.inventory.get(type,0))-int(source.deployment.get("counts",{}).get(type,0))','var generic := int(source.profile.inventory.get(type,0))-int(source.deployment.get("counts",{}).get(type,0))-int(source.profile.get("dorm",{}).get("storage",{}).get(type,0))')
    return t
stage('scripts/inventory_authority/ledger.gd',ledger)
def profile(t):
    t=replace(t,'extends RefCounted\n','extends RefCounted\nconst Dorm=preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")\n')
    t=replace(t,'\t\tif valid(parsed):data=parsed;return','\t\tif parsed is Dictionary and parsed.has("dorm") and not Dorm.valid(parsed.dorm,parsed.get("inventory",{}),parsed.get("component_instances",{})):\n\t\t\tdata=parsed;push_error("Corrupt dorm: original file retained; restore profile before playing");return\n\t\tif valid(parsed):\n\t\t\tdata=parsed\n\t\t\t_migrate_dorm(identity)\n\t\t\treturn')
    t=replace(t,'\tsave()\nstatic func valid','\t_migrate_dorm(identity)\n\tsave()\nfunc _migrate_dorm(profile_key: String) -> void:\n\tvar cfg := ConfigFile.new();cfg.load("user://student_identity.cfg")\n\tvar key := profile_key if not profile_key.is_empty() else "__default__"\n\tvar identity := str(cfg.get_value("profiles",key,""))\n\tif identity.is_empty():\n\t\tidentity=Crypto.new().generate_random_bytes(24).hex_encode();cfg.set_value("profiles",key,identity)\n\t\tif cfg.save("user://student_identity.cfg")!=OK:return\n\tvar result: Dictionary=Dorm.migrate(data,identity)\n\tif not result.ok:push_error(str(result.error));return\n\tif result.changed:\n\t\tvar before := data;data=result.profile\n\t\tif save()!=OK:data=before;push_error("Dorm migration save failed")\nstatic func valid')
    t=replace(t,'\tif not value is Dictionary or var_to_bytes(value).size()>1048576:return false','\tif not value is Dictionary or var_to_bytes(value).size()>1048576:return false\n\tif value.has("dorm") and not Dorm.valid(value.dorm,value.get("inventory",{}),value.get("component_instances",{})):return false')
    t=replace(t,'if int(payload.give[type])>int(data.inventory.get(type,0)):return "You no longer own all offered components"','if int(payload.give[type])+int(data.get("dorm",{}).get("storage",{}).get(type,0))>int(data.inventory.get(type,0)):return "Retrieve stored components before trading"')
    t=replace(t,'\tfor instance in payload.get("give_instances",{}):\n\t\tif not same','\tfor instance in payload.get("give_instances",{}):\n\t\tif instance in data.get("dorm",{}).get("instances",[]):return "Retrieve stored instance before trading"\n\t\tif not same')
    return t
stage('scripts/electronics_profile.gd',profile)
def network(t):
    t=replace(t,'signal operation_result(operation: String,result: Dictionary)','signal operation_result(operation: String,result: Dictionary)\nsignal profile_ready(peer: int)')
    t=replace(t,'\tsend_snapshot(peer,result)\n@rpc("any_peer","call_remote","reliable",6)\nfunc request_operation','\tsend_snapshot(peer,result)\n\tif result.get("ok",false):profile_ready.emit(peer)\n@rpc("any_peer","call_remote","reliable",6)\nfunc request_operation')
    t+='''
func submit_dorm(operation_id: String,intent: Dictionary) -> void:
\tif not game.session.online or operation_id.is_empty() or operation_id.length()>96 or pending.size()>=64:return
\tvar action := {"id":operation_id,"op":"dorm","args":[intent.duplicate(true)]}
\tfor waiting in pending:
\t\tif waiting.id==operation_id:return
\tpending.append(action);flush()
func local_storage_error(design: Dictionary) -> String:
\tif game.school.mode=="Creative Freeplay":return ""
\tvar profile: Dictionary=game.electronics.profile.data
\tvar stored: Dictionary=profile.get("dorm",{}).get("storage",{})
\tvar counts := {}
\tfor part in design.get("parts",[]):counts[part.type]=int(counts.get(part.type,0))+1
\tfor type in counts:
\t\tif int(counts[type])+int(stored.get(type,0))>int(profile.inventory.get(type,0)):return "Retrieve stored components before deploying"
\tfor id in design.get("instance_ids",{}).values():
\t\tif id in profile.get("dorm",{}).get("instances",[]):return "Retrieve stored instance before deploying"
\treturn ""
'''
    t=replace(t,'\t\t\tif instance not in result.instance_ids:result.instance_ids.append(instance)\n\treturn result','\t\t\tif instance not in result.instance_ids:result.instance_ids.append(instance)\n\tvar dorm: Dictionary=game.electronics.profile.data.get("dorm",{})\n\tfor type in dorm.get("storage",{}):result.counts[type]=int(result.counts.get(type,0))+int(dorm.storage[type])\n\tresult.instance_ids.append_array(dorm.get("instances",[]))\n\treturn result')
    return t
stage('scripts/inventory_authority/network.gd',network)
def dc(t):
    t=replace(t,'\t\t\t\taction.design=game.electronics_trade.authority.materialize(peer,action.design)','\t\t\t\tif not game.session.online:stock_error=game.electronics_trade.authority.local_storage_error(action.design)\n\t\t\t\tif stock_error=="":action.design=game.electronics_trade.authority.materialize(peer,action.design)')
    return t
stage('scripts/dc_lab.gd',dc)
def computers(t):
    t=replace(t,'var workspaces := {}','var workspaces := {}\nvar workspace_identities := {}')
    t=replace(t,'func request(action: Dictionary) -> void:', '''func set_private_owner(id: String,owner: String) -> bool:
\tif not stations.has(id):return false
\tstations[id].private_owner=owner
\tif multiplayer.is_server():
\t\tfor peer in sessions.keys():
\t\t\tif sessions[peer].station==id and not _private_allowed(peer,stations[id]):_close(peer,true)
\treturn true
func _identity(peer: int) -> String:
\tif not game.session.roster.has(peer):return ""
\treturn str(game.electronics_trade.authority.ledger.bindings.get(peer,"")) if game.session.online else (game.school.local_identity if peer==1 else "")
func _private_allowed(peer: int,entry: Dictionary) -> bool:
\treturn not entry.has("private_owner") or (not str(entry.private_owner).is_empty() and _identity(peer)==entry.private_owner)
func request(action: Dictionary) -> void:''')
    t=replace(t,'\t\tvar entry: Dictionary=stations[id]\n','\t\tvar entry: Dictionary=stations[id]\n\t\tif not _private_allowed(peer,entry):return\n')
    t=replace(t,'\t\tif sessions.has(peer):_reply(peer);return','\t\tif sessions.has(peer):\n\t\t\tvar previous: Dictionary=sessions[peer]\n\t\t\tif str(previous.get("identity",""))==_identity(peer) and _private_allowed(peer,stations[previous.station]):_reply(peer);return\n\t\t\t_close(peer,true)')
    t=replace(t,'\t\tsessions[peer]={"station":id,"lease":serial,"revision":0}','\t\tvar identity := _identity(peer)\n\t\tif workspace_identities.get(peer,"__unbound__")!=identity:\n\t\t\tworkspaces.erase(peer);restored.erase(peer)\n\t\tworkspace_identities[peer]=identity\n\t\tsessions[peer]={"station":id,"lease":serial,"revision":0,"identity":identity}')
    t=replace(t,'\tvar session: Dictionary=sessions[peer]\n','\tvar session: Dictionary=sessions[peer]\n\tif str(session.get("identity",""))!=_identity(peer) or not _private_allowed(peer,stations[session.station]):_close(peer,true);return\n')
    t=replace(t,'\tvar packet: Dictionary=sessions[peer].duplicate(true)','\tvar packet: Dictionary=sessions[peer].duplicate(true)\n\tpacket.erase("identity")')
    t=replace(t,'\tworkspaces.clear()','\tworkspaces.clear();workspace_identities.clear()')
    t=replace(t,'\t\t\tworkspaces.erase(peer)\n\t\t\trestored.erase(peer)','\t\t\tworkspaces.erase(peer);workspace_identities.erase(peer)\n\t\t\trestored.erase(peer)')
    t=replace(t,'if not game.session.roster.has(peer) or game.chairs[entry.chair].occupant!=peer:','if not game.session.roster.has(peer) or not _private_allowed(peer,entry) or game.chairs[entry.chair].occupant!=peer:')
    return t
stage('scripts/campus/computers/computer_sessions.gd',computers)
def instances(t):
    t=replace(t,'\tvar sorted_ids: Array=owned.keys();sorted_ids.sort()','\tvar sorted_ids: Array=owned.keys();sorted_ids.sort()\n\tvar stored: Array=profile.get("dorm",{}).get("instances",[])')
    t=replace(t,'if used.has(selected) or not owned.has(selected) or owned[selected].type!=part.type:selected=""','if selected in stored or used.has(selected) or not owned.has(selected) or owned[selected].type!=part.type:selected=""')
    t=replace(t,'if not used.has(id) and owned[id].type==part.type:selected=id;break','if id not in stored and not used.has(id) and owned[id].type==part.type:selected=id;break')
    return t
stage('scripts/inventory_authority/component_persistence.gd',instances)
def hall(t):
    t=replace(t,'\t_build_bed_storage(root, center, west)\n\t_build_workshop(root, contract.workshop_anchor, west)\n\t_build_loadout_notes(root, contract.loadout_notes_anchor, west)','\t# Furnishings are streamed by the persistent dorm coordinator.')
    return t
stage('scripts/campus/dorms/world/dorm_hall.gd',hall)
room_packet=ROOT/'review_artifacts/persistent_dorms_20261107/room'
stage('scripts/campus/dorms/integration/render_adapter.gd',lambda _:(PACK/'render_adapter.gd').read_text(encoding='utf-8-sig'))
def interior(_):
    t=(room_packet/'room_interior.gd').read_text(encoding='utf-8-sig')
    t=replace(t,'extends Node3D\n','extends Node3D\nconst SavedRenderer=preload("res://scripts/campus/dorms/integration/render_adapter.gd")\n')
    t=replace(t,'mesh.position=pos;add_child(mesh)','mesh.position=pos;add_child(mesh);SavedRenderer.mark(mesh,label)')
    t=replace(t,'add_child(body);targets[kind]=body','add_child(body);targets[kind]=body\n\tvar furnishing := {"computer":"desk_laptop","storage":"storage_cabinet"}.get(kind,kind)\n\tif furnishing in SavedRenderer.Dorm.DEFAULTS:body.set_meta("furniture",furnishing)')
    t=replace(t,'add_child(light);lamps[kind]=light','add_child(light);lamps[kind]=light;light.set_meta("furniture",kind)')
    t=t.replace('dx-.9,.26','dx-1.3,.26').replace('dx-.9,.73','dx-1.3,.73')
    return t
stage('scripts/campus/dorms/world/room_interior.gd',interior)
def room_adapter(_):
    t=(room_packet/'room_adapter.gd').read_text(encoding='utf-8-sig')
    t=t.replace('res://review_artifacts/persistent_dorms_20261107/room/room_interior.gd','res://scripts/campus/dorms/world/room_interior.gd')
    t=replace(t,'room.build(contract,public_projection.get("style",{}));room_id=id','room.build(contract,preload("res://scripts/campus/dorms/integration/render_adapter.gd").style(public_projection.get("customization",{})));room_id=id\n\t\tpreload("res://scripts/campus/dorms/integration/render_adapter.gd").apply(room,contract,public_projection.get("customization",{}))')
    assert 'authority.call("request_personal_computer",room_id)' in t,'room owner computer correction required'
    t=replace(t,'var router=game.get("dorm_interactions")','var router=game.get("dorm_interactions").router')
    return t
stage('scripts/campus/dorms/integration/room_adapter.gd',room_adapter)
stage('tests/campus/dorms/authority/test_persistent_memory.gd',lambda _:(PACK/'test_authority_memory.gd').read_text(encoding='utf-8-sig'))
for name in ['placement_rules.gd','room_edits.gd','edit_service.gd','decorate_panel.gd']:
    src=ROOT/'review_artifacts/persistent_dorms_20261107/customization/scripts/campus/dorms/customization'/name
    if src.exists():
        text=src.read_text(encoding='utf-8-sig')
        if name=='placement_rules.gd':
            text=text.replace('"study_desk":Vector2(1.55, 0.8)','"study_desk":Vector2(2.35, 1.1)').replace('"wardrobe":Vector2(1.45, 0.68)','"wardrobe":Vector2(1.35, 1.0)').replace('"shelf":Vector2(1.15, 0.38)','"shelf":Vector2(1.6, 0.38)')
        stage('scripts/campus/dorms/customization/'+name,lambda _,t=text:t)
for name in ['coordinator.gd']:
    stage('scripts/campus/dorms/integration/'+name,lambda _,n=name:(PACK/n).read_text(encoding='utf-8-sig'))
for path,entry in manifest.items():
    before=(PACK/'preimages'/path).read_text(encoding='utf-8')
    after=(OUT/path).read_text(encoding='utf-8')
    entry['patch']=''.join(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile=('a/'+path if entry['preimage_sha256'] else '/dev/null'),tofile='b/'+path))
(PACK/'PATCHES.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
(PACK/'integration.patch').write_text(''.join(x['patch'] for x in manifest.values()),encoding='utf-8')
dependencies={}
for folder in ['room','customization','rest']:
    for path in (ROOT/'review_artifacts/persistent_dorms_20261107'/folder).rglob('*'):
        if path.is_file() and path.suffix in ['.gd','.md','.patch']:
            dependencies[str(path.relative_to(ROOT)).replace('\\','/')]=hashlib.sha256(path.read_bytes()).hexdigest()
(PACK/'DEPENDENCIES.json').write_text(json.dumps(dependencies,indent=2),encoding='utf-8')
print('Staged',len(manifest),'files; production untouched')
