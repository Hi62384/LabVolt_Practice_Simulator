from pathlib import Path
import re,json,hashlib
root=Path.cwd(); out=root/'review_artifacts/ui_style_20261106'
decode_fallbacks=[]
def read_source(p):
    try: return p.read_text(encoding='utf-8-sig')
    except UnicodeDecodeError:
        decode_fallbacks.append(p.as_posix())
        return p.read_text(encoding='cp1252')
files={p.as_posix():read_source(p) for p in Path('scripts').rglob('*.gd')}
bases={'CanvasLayer','Control','PanelContainer','VBoxContainer','HBoxContainer','ScrollContainer','SubViewportContainer','Window','AcceptDialog'}
extra={'scripts/electronics_trade.gd','scripts/kit_world.gd','scripts/campus/ui/profile_visibility.gd','scripts/campus/ui/graphics_settings.gd','scripts/campus/facilities/circuit_studio/interaction_adapter.gd','scripts/campus/dorms/interactions/personal_station_router.gd'}
rows=[]
for path,src in files.items():
    if '/ui/design_system/' in path: continue
    m=re.search(r'^extends\s+(\w+)',src,re.M)
    if not m or (m[1] not in bases and path not in extra): continue
    funcs=[{'name':m[1],'line':src[:m.start()].count('\n')+1} for m in re.finditer(r'^func\s+(\w+)\(',src,re.M)]
    refs=[]
    for origin,code in files.items():
        for line,text in enumerate(code.splitlines(),1):
            if 'res://'+path in text: refs.append({'source':origin,'line':line,'code':text.strip()})
    rows.append({'path':path,'base':m[1],'sha256':hashlib.sha256(Path(path).read_bytes()).hexdigest(),'functions':funcs,'resource_references':refs,'dialog_constructors':[{'line':i,'code':line.strip()} for i,line in enumerate(src.splitlines(),1) if re.search(r'(FileDialog|AcceptDialog|ConfirmationDialog|Window)\.new\(',line)]})
(out/'SOURCE_SURFACES.json').write_text(json.dumps({'note':'Source inventory, not proof of runtime reachability. Resource references are exact string matches; routing via methods is documented in ADOPTION_MATRIX.md. Concurrent source may change after snapshot.','cp1252_fallbacks':decode_fallbacks,'surfaces':rows},indent=2)+'\n',encoding='utf-8')
print('Inventoried',len(rows),'UI source surfaces and routing adapters')
