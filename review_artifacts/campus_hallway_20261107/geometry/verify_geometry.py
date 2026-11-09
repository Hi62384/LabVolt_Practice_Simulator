import json
from pathlib import Path

root = Path(__file__).resolve().parents[3]
rooms = json.loads((root / 'assets/campus/world/room_registry.json').read_text())['rooms']
provider = (Path(__file__).parent / 'hallway_finish.gd').read_text()
assert len(rooms) == 16
assert all(r['door'][0] in (10, 16) for r in rooms)
assert all(r['door_width'] >= 2.4 for r in rooms)
assert all(r['door'][2] >= r['center'][2] - r['size'][2]/2 for r in rooms)
assert all(r['door'][2] <= r['center'][2] + r['size'][2]/2 for r in rooms)
assert 'world.material("a6b9b4").albedo_color' not in provider
assert 'false)' in provider and 'true)' not in provider
assert 'if z >= 50.0 and z <= 62.0 and x < 13.0: continue' in provider
assert 'HallwayGeometry.edge_closures()' in provider
assert '_add_floor_tiles(world, 0, -11.32, 68.0)' in provider
assert '_add_frame(world, face_x, center.y, door_z, half)' in provider
assert 'room.number' not in provider
print('PASS: 16 registry openings, no material mutation/collision, stair void guarded')

