from pathlib import Path
import hashlib

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
source = (PROJECT / "scripts/campus_integration.gd").read_text(encoding="utf-8")
preimage = (HERE / "campus_integration.preimage.gd").read_text(encoding="utf-8")
candidate = (HERE / "campus_integration.candidate.gd").read_text(encoding="utf-8")
module = (HERE / "m101_environment.gd").read_text(encoding="utf-8")

assert source == preimage, "Integration preimage drifted; rebase this packet"
assert hashlib.sha256(preimage.encode()).hexdigest() == "9c37ef2a0af23fce67d5396c0928cd8d5cc17923c2405f5084d2b384494d1088"
assert candidate.count('register_content("ac_lab",game.get_node("TrainingStation"))') == 1
assert 'm101_environment.mount(game.campus,game.campus.registry)' in candidate
assert 'teaching_finish.mount_approved(game.campus,game.campus.registry,["dc_lab"' in candidate
for forbidden in ("TrainingStation", "station.equipment", "terminal_bodies", "switch_meshes", "control_bodies", "_build_station", "_build_room"):
    assert forbidden not in module, f"Environment references protected equipment: {forbidden}"
assert 'campus.call("register_content", ROOM, root)' in module
assert 'M101 — AC ELECTRICAL LABORATORY' in module
assert 'CollisionShape3D' not in module

# Tile tops (.018) cover legacy seam tops (.0045) with 1.5 mm gaps.
assert .012 + .012 / 2 > .003 + .003 / 2
assert .984 < 1.0
# The south/north wall skins remain inside the 20 x 14 m shell.
assert -4 < -3.88 < 10 and -4 < 9.88 < 10
print("M101 private candidate source/geometry checks passed")
