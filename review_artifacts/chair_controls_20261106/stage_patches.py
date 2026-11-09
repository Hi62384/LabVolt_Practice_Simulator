"""Generate preimage-bound shared-file patches without editing shared files."""
from pathlib import Path
import difflib
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent

def stage(path, replacements):
    source = ROOT / path
    before = source.read_text(encoding="utf-8")
    after = before
    for old, new in replacements:
        assert after.count(old) == 1, (path, old[:70], after.count(old))
        after = after.replace(old, new, 1)
    diff = "".join(difflib.unified_diff(before.splitlines(True), after.splitlines(True),
        fromfile="a/" + path, tofile="b/" + path))
    name = path.replace("/", "__")
    (OUT / (name + ".patch")).write_text(diff, encoding="utf-8")
    return {"path": path, "preimage_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "proposed_sha256": hashlib.sha256(after.encode("utf-8")).hexdigest()}

entries = []
entries.append(stage("scripts/first_person.gd", [
    ('var seated: CharacterBody3D\n', 'var seated: CharacterBody3D\nvar seated_look = preload("res://scripts/campus/seating/chair_controls/look_state.gd").new()\nvar chair_entry_position := Vector3.ZERO\n'),
    ('func look(relative: Vector2) -> void:\n\tyaw_target -= relative.x*sensitivity\n\tpitch_target = clampf(pitch_target-relative.y*sensitivity,-1.46,1.46)\n',
     'func look(relative: Vector2) -> void:\n\tvar horizontal := -relative.x*sensitivity\n\tif is_instance_valid(seated):\n\t\tseated_look.look(horizontal, down("crouch"))\n\t\tyaw_target = seated_look.chair_turn\n\telse:\n\t\tyaw_target += horizontal\n\tpitch_target = clampf(pitch_target-relative.y*sensitivity,-1.46,1.46)\n'),
    ('\t\trotation.y=seated.swivel.rotation.y\n\t\teyes.rotation.x=',
     '\t\trotation.y=seated_look.world_yaw(seated.swivel.rotation.y)\n\t\teyes.rotation.x='),
    ('\tseated=chair\n\tchair.rider=self\n\tchair.previous_turn_target=yaw_target\n\tchair.turn_target=yaw_target\n\tchair.swivel.rotation.y=rotation.y\n',
     '\tchair_entry_position=global_position\n\tseated=chair\n\tchair.rider=self\n\tchair.swivel.rotation.y=rotation.y\n\tseated_look.enter(chair.swivel.rotation.y)\n\tyaw_target=seated_look.chair_turn\n\tchair.previous_turn_target=yaw_target\n\tchair.turn_target=yaw_target\n'),
    ('\t\t\tseated.rider=null\n\t\t\tseated=null\n\t\t\tglobal_position=destination\n',
     '\t\t\tyaw_target=seated_look.leave(seated.swivel.rotation.y)\n\t\t\trotation.y=yaw_target\n\t\t\tseated.rider=null\n\t\t\tseated=null\n\t\t\tglobal_position=destination\n'),
    ('\tfor offset in [Vector3(0,0,1),Vector3(1,0,0),Vector3(-1,0,0),Vector3(0,0,-1)]:\n\t\tvar destination: Vector3=seated.global_position+offset\n\t\tdestination.y=maxf(destination.y,0.02)\n\t\tvar query := PhysicsShapeQueryParameters3D.new()\n\t\tquery.shape=collider.shape\n\t\tquery.transform=Transform3D(Basis.IDENTITY,destination+Vector3(0,.85,0))\n\t\tquery.collision_mask=1\n\t\tif get_world_3d().direct_space_state.intersect_shape(query).is_empty():\n',
     '\tvar candidates: Array[Vector3]=[]\n\tif chair_entry_position.distance_to(seated.global_position)<3.0:\n\t\tcandidates.append(chair_entry_position)\n\tfor radius in [0.8,1.1,1.5,2.0]:\n\t\tfor step in range(16):\n\t\t\tvar angle := TAU*float(step)/16.0\n\t\t\tcandidates.append(seated.global_position+Vector3(sin(angle)*radius,0,cos(angle)*radius))\n\tfor candidate in candidates:\n\t\tvar floor_query := PhysicsRayQueryParameters3D.create(candidate+Vector3.UP*0.4,candidate-Vector3.UP*1.4,1,[get_rid(),seated.get_rid()])\n\t\tvar floor_hit := get_world_3d().direct_space_state.intersect_ray(floor_query)\n\t\tif floor_hit.is_empty() or floor_hit.normal.dot(Vector3.UP)<0.7:\n\t\t\tcontinue\n\t\tvar destination: Vector3=floor_hit.position+Vector3.UP*0.03\n\t\tif not SafeRecovery.is_known_walkable(destination):\n\t\t\tcontinue\n\t\tvar query := PhysicsShapeQueryParameters3D.new()\n\t\tquery.shape=collider.shape\n\t\tquery.transform=Transform3D(Basis.IDENTITY,destination+Vector3(0,.85,0))\n\t\tquery.collision_mask=1\n\t\tquery.exclude=[get_rid(),seated.get_rid()]\n\t\tif get_world_3d().direct_space_state.intersect_shape(query,8).is_empty():\n'),
]))
entries.append(stage("scripts/game.gd", [
    ('"WASD: roll  •  Mouse: swivel  •  Space: stand"',
     '"WASD: roll  •  Mouse: look ±90°  •  Ctrl + mouse: swivel  •  Space: stand"'),
    ('\tchair_input_times[peer]=Time.get_ticks_msec()\n\tfor i in range(chairs.size()):',
     '\tfor i in range(chairs.size()):'),
    ('\t\t\tif index==i:\n\t\t\t\tchair.drive=wish.limit_length(1)\n\t\t\t\tchair.turn_target=yaw\n',
     '\t\t\tif index==i:\n\t\t\t\tchair_input_times[peer]=Time.get_ticks_msec()\n\t\t\t\tchair.drive=wish.limit_length(1)\n\t\t\t\tchair.turn_target=yaw\n'),
]))
entries.append(stage("scripts/rolling_chair.gd", [
    ('\t\tturn_target=rider.yaw_target\n', '\t\tturn_target=rider.seated_look.chair_turn\n'),
]))
(OUT / "preimages.json").write_text(json.dumps(entries, indent=2) + "\n", encoding="utf-8")
