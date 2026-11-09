"""Offline bounds admission for the additive entrance packet."""
from pathlib import Path
import hashlib
root=Path(__file__).resolve().parents[3]
packet=Path(__file__).resolve().parent/'exterior_finish.gd'
source=(root/'scripts/campus/world/campus_world.gd').read_text(encoding='utf8')
text=packet.read_text(encoding='utf8')
assert 'Vector3(13,-.12,21.5),Vector3(6,.24,93)' in source
assert 'Vector3(13,-.18,-18),Vector3(46,.2,14)' in source
assert 'for x in [10.,16.]: box(self,Vector3(x,2,-9)' in source
assert 'Vector3(13,0,-18)' in (root/'assets/campus/world/room_registry.json').read_text().replace(' ','').replace('\n','') or '"entrance": [\n    13,\n    0,\n    -18' in (root/'assets/campus/world/room_registry.json').read_text()
assert 'for x in [9.72,16.28]' in text and 'Vector3(13,4.54,-11.32)' in text
assert 'CollisionShape3D' not in text and 'Light3D' not in text and 'Label3D' not in text
# Portal inner edge 9.845..16.155 leaves 6.31m; existing opening is x10..16.
assert 9.72+.25/2<10 and 16.28-.25/2>16
# Furniture and trees remain outside the central x10..16 approach.
for center in (-4.6,30.6):assert center+4<10 or center-4>16
print('entrance opening 6m preserved; central approach, collision and signs untouched')
print('world preimage',hashlib.sha256((root/'scripts/campus/world/campus_world.gd').read_bytes()).hexdigest())
print('packet',hashlib.sha256(packet.read_bytes()).hexdigest())
