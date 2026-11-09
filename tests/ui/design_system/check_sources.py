"""Bounded offline source/asset checks. This is NOT a GDScript parser or runtime test."""
from pathlib import Path
import hashlib,json,re,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'review_artifacts/ui_style_20261106'
SCRIPTS=ROOT/'scripts/ui/design_system'
checks=[]
def check(label,condition):
    if not condition: raise AssertionError(label)
    checks.append(label)
def luminance(value):
    rgb=[int(value[i:i+2],16)/255 for i in (0,2,4)]
    channels=[v/12.92 if v<=0.04045 else ((v+0.055)/1.055)**2.4 for v in rgb]
    return sum(v*w for v,w in zip(channels,[.2126,.7152,.0722]))
def contrast(a,b):
    high,low=sorted([luminance(a),luminance(b)],reverse=True)
    return (high+.05)/(low+.05)
all_source='\n'.join(p.read_text(encoding='utf-8-sig') for p in SCRIPTS.glob('*.gd'))
refs=re.findall(r'(?:preload|load)\("res://([^\"]+)"\)',all_source)
check('Every design-system resource reference resolves',all((ROOT/p).is_file() for p in refs))
check('Runtime modules depend only on owned design-system scripts/assets',all('/ui/design_system/' in p for p in refs))
check('No game, save, network or economy APIs in presentation layer',not re.search(r'(user://|\.rpc\b|\.rpc_id\b|authority_submit|FileAccess|ConfigFile|\.request\(|\.save\(|\.purchase\()',all_source))
icons=list((ROOT/'assets/ui/design_system/icons').glob('*.svg'))
check('42 original icons are present',len(icons)==42)
for p in icons:
    tree=ET.fromstring(p.read_text(encoding='utf-8'))
    check(f'{p.stem} icon is bounded SVG without external content',tree.attrib.get('viewBox')=='0 0 24 24' and all(node.tag.split('}')[-1] in {'svg','path'} for node in tree.iter()) and 'href' not in ET.tostring(tree,encoding='unicode'))
widgets=(SCRIPTS/'widgets.gd').read_text(encoding='utf-8-sig')
keys=set(re.findall(r'^\s*"([a-z_]+)": preload',widgets,re.M))
check('Every SVG is explicitly allowlisted',keys=={p.stem for p in icons})
check('API version and published factories exist',all(re.search(r'static func '+name+r'\(',widgets) for name in ['action','text','header','card','field','field_error','badge','style_button','action_icon','section','status','empty_state']))
measurements=[]
for foreground,background in [('edf6fa','142b38'),('b6cad4','142b38'),('b6cad4','1d3b4a'),('edf6fa','285c59'),('ffb6b9','352a38'),('94aab7','243642')]:
    ratio=contrast(foreground,background); measurements.append({'foreground':foreground,'background':background,'ratio':round(ratio,2)})
    check(f'Text contrast {foreground}/{background} >= 4.5:1',ratio>=4.5)
for rarity in ['c4d3dc','9cddb2','9fcfff','d5b5ff','ffe09e','a4e9e2']:
    check(f'Rarity label {rarity} contrast >= 4.5:1',contrast(rarity,'1d3b4a')>=4.5)
check('Fixture is additive, absent from project startup', 'ui/design_system' not in (ROOT/'project.godot').read_text(encoding='utf-8-sig'))
check('Fixture and deferred engine test exist',(ROOT/'scenes/ui/design_system/review.tscn').is_file() and (ROOT/'tests/ui/design_system/test_design_system.gd').is_file())
plans=json.loads((OUT/'adoption_patches.json').read_text(encoding='utf-8'))['patches']
patch_status=[]
for plan in plans:
    raw=(ROOT/plan['path']).read_bytes()
    same=hashlib.sha256(raw).hexdigest()==plan['source_sha256']
    if same:
        source=raw.decode('utf-8-sig').replace('\r\n','\n')
        for edit in plan['edits']:
            check(f"Unique patch preimage: {plan['path']}",source.count(edit['before'])==1)
            source=source.replace(edit['before'],edit['after'],1)
        check(f"Patch postimage hash: {plan['path']}",hashlib.sha256(source.encode()).hexdigest()==plan['normalized_after_sha256'])
    patch_status.append({'path':plan['path'],'state':'preimage_matches_staged_only' if same else 'owner_changed_do_not_apply','current_sha256':hashlib.sha256(raw).hexdigest()})
report={'scope':'Offline source/assets only; no GDScript parse, Godot process, visual render, gameplay, save or multiplayer acceptance performed.','passed_checks':len(checks),'contrast':measurements,'patches':patch_status,'owned_files':[{'path':p.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for folder in ['scripts/ui/design_system','assets/ui/design_system','scenes/ui/design_system','tests/ui/design_system'] for p in sorted((ROOT/folder).rglob('*')) if p.is_file() and '__pycache__' not in p.as_posix()]}
(OUT/'source_checks.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'passed_checks':len(checks),'scope':report['scope'],'patch_preimages_matching':sum(p['state']=='preimage_matches_staged_only' for p in patch_status),'patch_owner_changes':sum(p['state']=='owner_changed_do_not_apply' for p in patch_status)},indent=2))
