from pathlib import Path
import hashlib,json,re
root=Path(__file__).resolve().parent
session=(root/'computer_sessions.gd').read_text()
vfs=(root/'virtual_files.gd').read_text()
local=(root/'local_documents.gd').read_text()
assert '_private.rpc_id(peer,packet)' in session
assert not re.search(r'_private\.rpc\(',session)
assert 'multiplayer.get_remote_sender_id(),action' in session
assert 'action.has("owner")' in session
assert 'action.get("lease",-1)!=session.lease' in session
assert 'action.get("revision",-1)!=session.revision' in session
assert 'game.school.apply(peer,a)' in session
assert 'workspaces.erase(peer)' in session and 'restored.erase(peer)' in session
assert 'Files.validate(files)' in session
assert 'game.school._public_project(paper.project' in session
assert 'packet.papers' not in session
assert 'game._stand_from_chair()' in session
assert 'game.release_mouse()' in (root/'classroom_adapter.gd').read_text()
assert 'ComputerSessions' in (root/'assembly_shared_patches.json').read_text()
assert 'MAX_FILES := 32' in vfs and 'MAX_TOTAL_BYTES := 262144' in vfs
for forbidden in ['OS.execute','OS.create_process','HTTPClient','HTTPRequest','JavaScriptBridge']:
    assert forbidden not in session+vfs+local
assert 'user://' not in session+vfs
assert 'identity.sha256_text()' in local
print('PASS: 20 source boundary checks; not a Godot parse or runtime result')
manifest={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in root.iterdir() if p.is_file() and p.name!='SHA256.json'}
(root/'SHA256.json').write_text(json.dumps(manifest,indent=2)+'\n')
