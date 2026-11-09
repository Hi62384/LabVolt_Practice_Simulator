"""Non-engine audit. This does not claim runtime, network, or visual acceptance."""
from pathlib import Path
import hashlib
import json
import re

BASE = Path(__file__).resolve().parent
ROOT = BASE.parents[1]
checks = []
def check(value, label):
    assert value, label
    checks.append(label)

manifest = json.loads((BASE / 'manifest.json').read_text())
for item in manifest:
    source = (ROOT / item['path']).read_bytes()
    check(hashlib.sha256(source).hexdigest() == item['preimage_sha256'], 'production preimage intact: ' + item['path'])
    candidate = (BASE / (item['path'].replace('/', '__') + '.proposed')).read_bytes()
    check(hashlib.sha256(candidate).hexdigest() == item['candidate_sha256'], 'candidate digest: ' + item['path'])

registry = json.loads((ROOT / 'assets/campus/world/room_registry.json').read_text())
check(sorted(set(int(r['floor']) for r in registry['rooms'])) == [0, 1], 'only actual floors 0 and 1')
geometry = (BASE / 'elevator_geometry.gd').read_text()
state = (BASE / 'elevator_state.gd').read_text()
service = (BASE / 'elevator_service.gd').read_text()
world = (BASE / 'scripts__campus__world__campus_world.gd.proposed').read_text()
integration = (BASE / 'scripts__campus_integration.gd.proposed').read_text()
hall = (ROOT / 'scripts/campus/presentation/navigation_safety/hallway_geometry.gd').read_text()
check('Vector3(15.75, -0.25, 56.0), Vector3(8.25, 5.5, 4.0)' in hall, 'adopted hallway protected entrance contract')
check('Vector3(16.0, y + 2, z), Vector3(0.08, 4, 2)' in geometry, 'front wall pockets leave original 2m aperture')
check('Vector3(20, y - 0.12, 59), Vector3(8, 0.24, 6)' in geometry, 'existing landing floor dimensions and top Y0/5 preserved')
check('Vector3(8, 0.18, 6)' in geometry, 'full original cabin footprint roof')
check('Vector3(0.22, 3, 2)' in geometry and 'active and phase == "open"' in geometry, 'full doorway collision released only at authoritative fully open phase')
# Evaluate the actual door formula constants: closed leaves cover 58..60;
# open leaves are fully outside the aperture and wholly in the pocket spans.
half_leaf = 0.995 / 2
closed = [(59 + side * .5 - half_leaf, 59 + side * .5 + half_leaf) for side in [-1, 1]]
opened = [(59 + side * 1.55 - half_leaf, 59 + side * 1.55 + half_leaf) for side in [-1, 1]]
check(closed[0][0] >= 58 and closed[1][1] <= 60 and closed[1][0] - closed[0][1] < .006, 'closed leaves match existing doorway')
check(16.18 - .09 / 2 > 16.08 and 16.18 + .09 / 2 < 16.35 - .08 / 2, 'door plane clears original corridor wall and new rear pocket skin')
check(opened[0][1] < 58 and opened[1][0] > 60 and opened[0][0] >= 56 and opened[1][1] <= 62, 'fully open leaves clear aperture within original pockets')
check('Vector3(10.55, y + 0.46, 64.4)' in geometry and 'Vector3(10.55, y + 0.25, 66)' in geometry, 'bench and plant outside cabin, stairs and X13..16 upper corridor')
check('elevator_validator' not in world and 'actor.global_position=destination' not in world, 'old requester-only teleport removed')
check('func _elevator_request(' not in integration and 'func _elevator(peer:' not in integration, 'no competing legacy transport RPC')
check('integration._relocate(int(peer), point)' in service and 'for peer in state.riders:' in service, 'existing epoch relocation reused for entire rider set')
check('riders = occupants.duplicate(true)' in state and 'elif elapsed >= DOOR_SECONDS' in state, 'riders captured on closing completion')
check('_phase("opening")' in state and 'if blocked or not eligible:' in state, 'obstruction and invalid occupants reopen')
check('if cabin and phase != "open": return false' in state, 'moving cabin selections rejected')
check('previous_guard.call(peer, proposed, previous)' in service and 'previous_local_lock.call()' in service, 'existing facility movement guards composed')
check('game.session.restarted.connect(_reset)' in service and 'state.forget(peer)' in service, 'disconnect and session-reset paths installed')
check('timer.stop()' in service and 'if state.revision != revision: _publish()' in service, 'idle processing stops and replication occurs on state edges')
check('"reliable", 4' in service and '"authority"' in service and '"any_peer"' in service, 'request/snapshot RPC authority and ordered relocation channel')
check('res://assets/' not in geometry and 'material_override' in geometry, 'private materials; no device resource or global material mutations')
result = {'kind':'source and geometry arithmetic only', 'checks':len(checks), 'passed':checks, 'runtime':'NOT RUN: reserved runtime owner', 'network':'NOT RUN', 'screenshots':'NOT CAPTURED'}
(BASE / 'source_checks.json').write_text(json.dumps(result, indent=2) + '\n')
print('PASS', len(checks), 'source/geometry checks; engine, actual transport, collision and visual evidence pending.')
