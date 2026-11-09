from pathlib import Path
from hashlib import sha256
from difflib import unified_diff

packet = Path(__file__).resolve().parent
root = packet.parents[1]
patches = []
hashes = []

def stage(name, changes):
    raw = (root / name).read_bytes()
    old = raw.decode('utf-8-sig').replace('\r\n', '\n')
    new = old
    for before, after in changes:
        assert new.count(before) == 1, (name, before)
        new = new.replace(before, after, 1)
    hashes.append(f'{sha256(raw).hexdigest()}  {name}')
    patches.extend(unified_diff(old.splitlines(True), new.splitlines(True), 'a/'+name, 'b/'+name))

pending = 'scripts/campus/academics/pending_assessment.gd'
pending_source = (root / pending).read_text(encoding='utf-8-sig')
stage(pending, [(pending_source[pending_source.index('static func abandoned('):], '''## Reconcile only the named session on orderly host exit. On process startup,
## every persisted class has ended because class sessions cannot resume.
static func end_host_session(archive: Dictionary, persist: Callable, session_id: String = "") -> Error:
	var next := archive.duplicate(true)
	var changed := false
	for token in next:
		var entries: Variant = next[token]
		if not entries is Dictionary:continue
		for id in entries.keys():
			var record: Variant = entries[id]
			if not record is Dictionary or record.get("pending_assessment_version") != VERSION or record.has("score"):continue
			if session_id != "" and str(record.get("assessment_id", "")) != session_id:continue
			changed = true
			if record.get("class_authority_role") == "host" and str(record.get("profile", "")) == str(token) and str(record.get("id", "")) == str(id):
				record.erase("pending_assessment_version")
				record["score"] = 0.0
				record["reason"] = "Hosted class ended before the assignment was completed."
			else:
				# Guest work is interrupted. Legacy entries have no reliable role.
				entries.erase(id)
	if not changed:return OK
	var error: Error = persist.call(next)
	if error != OK:return error
	archive.clear()
	archive.merge(next, true)
	return OK
''')])

stage('scripts/school_session.gd', [
    ('''\t_identity_changed()
\tfor result in PendingAssessment.abandoned(archive,local_identity):
\t\tif PendingAssessment.settle(archive,result,_persist_archive)==OK:_receive_grade(result)''', '''\tif PendingAssessment.end_host_session(archive,_persist_archive)!=OK:
\t\tpush_warning("Could not reconcile interrupted class records. The archive will be retried on the next launch.")
\t_identity_changed()'''),
    ('\tsent_identity=false\n\tif game.front.page=="characters":', '\tsent_identity=false\n\t_deliver_host_departure_grade()\n\tif game.front.page=="characters":'),
    ('_enrollment_record(token,assessment_id,project)', '_enrollment_record(token,assessment_id,project,peer==1)'),
    ('\t\tif PendingAssessment.prepare(archive,obligation,_persist_archive)!=OK:return 0', '\t\tobligation["class_authority_role"]="host" if peer==1 else "guest"\n\t\tif PendingAssessment.prepare(archive,obligation,_persist_archive)!=OK:return 0'),
    ('func _enrollment_record(token: String, session_id: String, assignment: Dictionary) -> Dictionary:', 'func _enrollment_record(token: String, session_id: String, assignment: Dictionary, is_host: bool) -> Dictionary:'),
    ('\trecord.merge(CourseProgression.record_fields(assignment),true)\n\tvar assessment', '\trecord["class_authority_role"]="host" if is_host else "guest"\n\trecord.merge(CourseProgression.record_fields(assignment),true)\n\tvar assessment'),
    ('enrollment.append(_enrollment_record(str(profile),next_assessment_id,assignment))', 'enrollment.append(_enrollment_record(str(profile),next_assessment_id,assignment,str(profile)==str(identities.get(1,local_identity))))'),
    ('''\t\t\thost_departure_in_progress=true
\t\t\t_fail_departing(str(identities.get(1,local_identity)),1)''', '''\t\t\thost_departure_in_progress=true
\t\t\tif formal_active() and not assessment_id.is_empty():
\t\t\t\tif PendingAssessment.end_host_session(archive,_persist_archive,assessment_id)==OK:
\t\t\t\t\t_deliver_host_departure_grade()
\t\t\t\telse:push_warning("Could not close class records. The archive will be retried on the next launch.")'''),
    ('func prepare_host_exit(intentional: bool) -> void:', '''func _deliver_host_departure_grade() -> void:
\tfor record in archive.get(local_identity,{}).values():
\t\tif not record is Dictionary or record.get("class_authority_role")!="host" or record.get("profile")!=local_identity:continue
\t\tif record.get("reason")!="Hosted class ended before the assignment was completed." or not record.has("score"):continue
\t\tif not gradebook.has(str(record.get("id",""))):_receive_grade(record)

func prepare_host_exit(intentional: bool) -> void:'''),
])

stage('scripts/session.gd', [
    ('multiplayer.server_disconnected.connect(func(): leave();', 'multiplayer.server_disconnected.connect(func(): leave(true);'),
    ('func leave() -> void:', 'func leave(authority_lost := false) -> void:'),
    ('set_meta("lost_authority",disconnected and not was_host)', 'set_meta("lost_authority",authority_lost or (disconnected and not was_host))'),
    ('\tif not multiplayer.is_server():\n\t\treturn\n\troster.erase(id)', '\tif not multiplayer.is_server():\n\t\treturn\n\tif online and was_host and multiplayer.multiplayer_peer.get_connection_status()==MultiplayerPeer.CONNECTION_DISCONNECTED:return\n\troster.erase(id)'),
    ('func _process(_delta: float) -> void:\n\tif appearance_queue', 'func _process(_delta: float) -> void:\n\tif online and was_host and multiplayer.multiplayer_peer.get_connection_status()==MultiplayerPeer.CONNECTION_DISCONNECTED:\n\t\tleave()\n\t\treturn\n\tif appearance_queue'),
])

(packet / 'host_departure.patch').write_bytes(''.join(patches).encode())
(packet / 'PREIMAGES.sha256').write_text('\n'.join(hashes)+'\n', encoding='utf-8')
