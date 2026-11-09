from pathlib import Path
import re,json,hashlib
owned=Path('scripts/ui/design_system'); exports={}
for p in owned.glob('*.gd'):
    src=p.read_text(encoding='utf-8-sig')
    exports['res://'+p.as_posix()]=set(re.findall(r'^(?:static )?func\s+(\w+)\(',src,re.M)+re.findall(r'^const\s+(\w+)',src,re.M)+['new'])
rows=[];missing=[]
for p in Path('scripts').rglob('*.gd'):
    if '/ui/design_system/' in p.as_posix():continue
    try:src=p.read_text(encoding='utf-8-sig')
    except UnicodeDecodeError:src=p.read_text(encoding='cp1252')
    for m in re.finditer(r'const\s+(\w+)\s*=\s*preload\("(res://scripts/ui/design_system/[^\"]+)"\)',src):
        alias,path=m.groups()
        if path not in exports:missing.append({'path':p.as_posix(),'missing_resource':path});continue
        symbols=sorted(set(re.findall(r'\b'+re.escape(alias)+r'\.(\w+)',src)))
        absent=sorted(set(symbols)-exports[path])
        rows.append({'path':p.as_posix(),'resource':path,'symbols':symbols,'missing':absent})
        if absent:missing.append(rows[-1])
report={'scope':'Source symbol check only; no GDScript parsing or runtime validation. Captures const preload aliases, not dynamic load aliases.','consumer_imports':len(rows),'missing':missing,'consumers':rows}
Path('review_artifacts/ui_style_20261106/API_CONSUMERS.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'consumer_imports':len(rows),'missing':missing}))
assert not missing
