"""Create exact-preimage candidates only; never modifies production files."""
from pathlib import Path
import difflib
import hashlib
import json

BASE = Path(__file__).resolve().parent
ROOT = BASE.parents[1]
manifest = []

def stage(name, transform):
    path = ROOT / name
    original = path.read_bytes()
    old = original.decode('utf-8-sig').replace('\r\n', '\n')
    new = transform(old)
    assert old != new, name
    prefix = BASE / name.replace('/', '__')
    Path(str(prefix) + '.preimage').write_bytes(original)
    candidate = new.replace('\n', '\r\n').encode('utf-8') if b'\r\n' in original else new.encode('utf-8')
    Path(str(prefix) + '.proposed').write_bytes(candidate)
    patch = ''.join(difflib.unified_diff(old.splitlines(True), new.splitlines(True), fromfile='a/' + name, tofile='b/' + name))
    Path(str(prefix) + '.patch').write_text(patch, encoding='utf-8')
    manifest.append({'path':name, 'preimage_sha256':hashlib.sha256(original).hexdigest(), 'candidate_sha256':hashlib.sha256(candidate).hexdigest()})

def world(s):
    s = s.replace('signal elevator_requested(actor: Node3D, destination: Vector3)', 'signal elevator_control_requested(floor_id: int, button: int)')
    s = s.replace('var elevator_validator: Callable', 'var elevator_geometry: Node3D')
    start = s.index('func _elevator() -> void:')
    end = s.index('func _paving()', start)
    return s[:start] + '''func _elevator() -> void:
	elevator_geometry = preload("res://scripts/campus/elevator/elevator_geometry.gd").new()
	elevator_geometry.name = "ElevatorGeometry"
	add_child(elevator_geometry)
	elevator_geometry.mount(self)

func interact(target: Node, actor: Node3D) -> bool:
	if not is_instance_valid(target) or target.get_meta("role", "") != "elevator_control": return false
	if not elevator_geometry.is_ancestor_of(target): return false
	if not is_instance_valid(actor) or actor.global_position.distance_to(target.global_position) > 3: return true
	elevator_control_requested.emit(int(target.get_meta("floor")), int(target.get_meta("button")))
	return true

''' + s[end:]

def integration(s):
    s = s.replace('var game: Node', 'var elevator_service: Node\nvar game: Node', 1)
    s = s.replace('\tgame.campus.elevator_requested.connect(_elevator_requested)\n', '')
    needle = '\tfacilities.install_movement_hooks(game.session,game.player)'
    assert s.count(needle) == 1
    s = s.replace(needle, needle + '''
	elevator_service=preload("res://scripts/campus/elevator/elevator_service.gd").new()
	elevator_service.name="ElevatorService";add_child(elevator_service)
	elevator_service.configure(self)
	game.campus.elevator_control_requested.connect(elevator_service.request)''')
    start = s.index('func _elevator_requested(')
    assert 'func ' not in s[s.index('\t_relocate(peer,Vector3(14.5', start):]
    return s[:start]

def hud(s):
    needle = '\t\telif role=="dc_panel":'
    assert s.count(needle) == 1
    return s.replace(needle, '\t\telif role=="elevator_control":\n\t\t\thint="E / click: "+str(current_target.get_meta("label","Elevator"))\n' + needle)

def world_test(s):
    start = s.index('\tvar target: Node\n')
    end = s.index('\tprint("WORLD_METRICS', start)
    return s[:start] + '''	var target: Node
	for child in campus.elevator_geometry.get_children():
		if child.get_meta("role", "") == "elevator_control": target=child; break
	check(is_instance_valid(target), "physical elevator controls mounted")
	var actor := Node3D.new()
	campus.add_child(actor); actor.global_position=target.global_position
	var old: Vector3=actor.position
	var calls := [0]
	campus.elevator_control_requested.connect(func(_floor, _button): calls[0]+=1)
	campus.interact(target,actor)
	check(actor.position==old, "world never bypasses host multi-rider service")
	check(calls[0]==1, "physical control requests authoritative service")
	actor.position=Vector3.ZERO; campus.interact(target,actor)
	check(calls[0]==1, "remote control rejected")
''' + s[end:]

stage('scripts/campus/world/campus_world.gd', world)
stage('scripts/campus_integration.gd', integration)
stage('scripts/game.gd', hud)
stage('tests/campus/world/world_tests.gd', world_test)
(BASE / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('Staged', len(manifest), 'exact-preimage patches. Production unchanged.')
