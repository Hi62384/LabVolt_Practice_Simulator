from pathlib import Path
import json,hashlib
p=Path('review_artifacts/ui_style_20261106/FOCUSED_INTEGRATION.json');data=json.loads(p.read_text())
for change in data['changes']:
 raw=Path(change['path']).read_bytes();assert hashlib.sha256(raw).hexdigest()==change['sha256'],change['path']
 old=raw.decode('utf-8-sig').replace('\r\n','\n');new=old
 for edit in change['edits']:
  assert new.count(edit['old'])==1,change['path'];new=new.replace(edit['old'],edit['new'],1)
 assert new!=old
print('Focused patch preimages and replacements verified; source files unchanged')
