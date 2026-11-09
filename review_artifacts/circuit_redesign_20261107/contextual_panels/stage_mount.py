from pathlib import Path
import hashlib,difflib,json
source=Path('review_artifacts/circuit_redesign_20261107/core/modules/workspace.gd');raw=source.read_bytes();old=raw.decode('utf-8-sig').replace('\r\n','\n')
needle='\tcanvas.selection_updated.connect(func(ids):selection_changed.emit(ids))\n'
assert old.count(needle)==1
insert=needle+'\tvar contextual := preload("res://scripts/electronics/contextual_panels/panel_host.gd").new()\n\tcanvas.add_child(contextual)\n\tcontextual.configure(self,callbacks.get("panel_data",{}),callbacks.get("panel_actions",{}))\n'
new=old.replace(needle,insert,1)
out=Path('review_artifacts/circuit_redesign_20261107/contextual_panels')
(out/'CORE_WORKSPACE_MOUNT.patch').write_text(''.join(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='a/review_artifacts/circuit_redesign_20261107/core/modules/workspace.gd',tofile='b/review_artifacts/circuit_redesign_20261107/core/modules/workspace.gd',n=4)),encoding='utf-8')
(out/'CORE_WORKSPACE_MOUNT.json').write_text(json.dumps({'state':'staged_only_for_core_owner','path':source.as_posix(),'sha256':hashlib.sha256(raw).hexdigest(),'old':needle,'new':insert,'normalized_after_sha256':hashlib.sha256(new.encode()).hexdigest()},indent=2)+'\n',encoding='utf-8')
print('Staged exact mount patch for core private workspace')
