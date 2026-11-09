from pathlib import Path
import hashlib, json
ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
manifest = json.loads((HERE / 'manifest.json').read_text())
path = 'scripts/pcb_design/editor.gd'
entry = next(e for e in manifest if e['path'] == path)
target = ROOT / path
before = target.read_bytes()
assert hashlib.sha256(before).hexdigest() == entry['after_sha256'], 'Concurrent PCB edit'
text = before.decode().replace('\r\n','\n')
for old, new in [
    ('var mode: OptionButton\n', 'var mode: OptionButton\nvar outline_group: PanelContainer\nvar copper_group: PanelContainer\n'),
    ('\thelp.text="Drag a numbered', '\toutline_group.visible=index==0;copper_group.visible=index==1\n\thelp.text="Drag a numbered'),
    ('\tChrome.section(self,"Outline geometry", "settings", outline_tools, dimensions)\n\tChrome.section(self,"Copper and placement", "component", trace_tools, component_tools)',
     '\toutline_group=Chrome.section(self,"Outline geometry", "settings", outline_tools, outline_tools)\n\tChrome.section(self,"Board dimensions", "settings", sizes, dimensions)\n\tcopper_group=Chrome.section(self,"Copper and placement", "component", trace_tools, component_tools)'),
    ('\tChrome.labeled(pads,"Component or land")', '\tChrome.labeled(pads,"Component or land")\n\tChrome.labeled(snap,"Outline snap · grid units")'),
]:
    assert text.count(old) == 1, old
    text = text.replace(old,new)
assert target.read_bytes() == before
data=text.replace('\n','\r\n').encode()
target.write_bytes(data)
entry['after_sha256']=hashlib.sha256(data).hexdigest()
(HERE / 'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('PCB workflow cards follow outline/copper mode; size controls remain accessible.')
