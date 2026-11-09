from pathlib import Path
import hashlib,difflib,json
path=Path('scripts/electronics_ui.gd');raw=path.read_bytes();old=raw.decode('utf-8-sig').replace('\r\n','\n')
needle='\tvar tabs := HBoxContainer.new();column.add_child(tabs)\n\tif page!="shop":\n\t\tfor entry in [["inventory","Hotbar"],["shop","Components"],["kits","My kits"],["board","Breadboard"],["notes","Notebook"],["ics","IC / PCB builder"],["code","Code"],["trade","Trade"]]:button(tabs,entry[1],func():open(entry[0],bench))\n'
assert old.count(needle)==1
new=old.replace(needle,'',1)
out=Path('review_artifacts/ui_style_20261106')
(out/'REMOVE_CROSS_STATION_NAV.patch').write_text(''.join(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='a/scripts/electronics_ui.gd',tofile='b/scripts/electronics_ui.gd',n=5)),encoding='utf-8')
(out/'REMOVE_CROSS_STATION_NAV.json').write_text(json.dumps({'state':'staged_only','path':path.as_posix(),'sha256':hashlib.sha256(raw).hexdigest(),'preimage':needle,'postimage':'','new_sha256_normalized':hashlib.sha256(new.encode()).hexdigest()},indent=2)+'\n',encoding='utf-8')
print('Staged one exact source replacement; live source unchanged')
