from pathlib import Path
import hashlib,json,re
p=Path('review_artifacts/ui_style_20261106/REMOVE_CROSS_STATION_NAV.json');spec=json.loads(p.read_text())
raw=Path(spec['path']).read_bytes();assert hashlib.sha256(raw).hexdigest()==spec['sha256'],'Shared file changed; do not apply candidate'
s=raw.decode('utf-8-sig').replace('\r\n','\n');assert s.count(spec['preimage'])==1
candidate=s.replace(spec['preimage'],spec['postimage'],1)
assert hashlib.sha256(candidate.encode()).hexdigest()==spec['new_sha256_normalized']
open_body=candidate.split('func open(page := "shop",index := -1) -> void:',1)[1].split('func shop()',1)[0]
assert 'for entry in [["inventory","Hotbar"]' not in open_body
assert 'var tabs := HBoxContainer.new();column.add_child(tabs)' not in open_body
assert 'button(bar,"Close",close)' in open_body
for page in ['inventory','shop','kits','board','design','notes','ics','code','kit_world','trade']:
 assert f'"{page}":' in open_body or (page in ['board','design'] and '"board", "design":' in open_body)
for source,fragment in {
 'scripts/shop_room.gd':'else:game.electronics.open(page)',
 'scripts/campus/dorms/interactions/personal_station_router.gd':'game.electronics.open(page)',
 'scripts/campus/facilities/circuit_studio/interaction_adapter.gd':'game.electronics.open(page)',
 'scripts/game.gd':'event.keycode==KEY_I:electronics.open("inventory")',
}.items(): assert fragment in Path(source).read_text(encoding='utf-8-sig'),source
assert 'open("design",bench)' in candidate and 'open("code",bench)' in candidate
print('Candidate verified: all 10 page dispatches, Close, physical routes and intentional local/keyboard actions remain; no shared bar constructor')
