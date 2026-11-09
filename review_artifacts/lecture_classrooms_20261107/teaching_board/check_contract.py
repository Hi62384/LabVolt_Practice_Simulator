"""Static board integration checks. Does not launch Godot or touch save data."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WORLD = (ROOT / "scripts/school_world.gd").read_text(encoding="utf-8")
SESSION = (ROOT / "scripts/school_session.gd").read_text(encoding="utf-8")
BOARD = (Path(__file__).parent / "teaching_board.gd").read_text(encoding="utf-8")
PATCH = (Path(__file__).parent / "integration.patch").read_text(encoding="utf-8")

for line in PATCH.splitlines():
    if line.startswith("-") and not line.startswith("---"):
        assert line[1:] in WORLD, f"stale preimage: {line[1:100]}"

assert 'if presentation.get("current_only",false)' in SESSION
assert 'safe.stages=[teaching_stage().duplicate(true)]' in SESSION
assert 'school.teaching_stage() if school.phase=="lesson"' in PATCH
assert 'if not active:return' in BOARD
assert 'if key == signature:return' in BOARD
assert 'SubViewport.UPDATE_ONCE' in BOARD
assert 'SubViewport.UPDATE_DISABLED' in BOARD
for kind in ['"graph"', '"circuit"', '"netlist"', '"statistics"', '"table"', '"image"']:
    assert kind in BOARD
assert 'path.begins_with("res://assets/")' in BOARD
assert 'diagram_action_requested.emit' in BOARD
print("Teaching board contract and current preimage checks passed")
