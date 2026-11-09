from pathlib import Path
import hashlib,json
base=Path(__file__).resolve().parents[3]
root=Path(__file__).resolve().parent
p=base/'scripts/game.gd'
b=p.read_bytes(); text=b.decode('utf-8-sig')
edits=[{'old':'var school: Node','new':'var school: Node\nvar computers: Node'}, {'old':'\tschool.build(self)','new':'\tschool.build(self)\n\tcomputers=preload("res://scripts/campus/computers/computer_sessions.gd").new()\n\tcomputers.name="ComputerSessions"\n\tadd_child(computers)\n\tcomputers.build(self)'}]
for edit in edits:
    assert text.count(edit['old'])==1
(root/'game_shared_patch.json').write_text(json.dumps({'path':'scripts/game.gd','preimage_sha256':hashlib.sha256(b).hexdigest(),'edits':edits},indent=2)+'\n')
(root/'game.gd.preimage').write_bytes(b)
print('Staged exact-preimage game integration patch; live file unchanged')
