"""Offline source/geometry gate for the proposed M101 floor patch."""
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[4]
def run():
    game=(ROOT/'scripts/game.gd').read_text(encoding='utf8')
    equipment=(ROOT/'scripts/equipment_builder.gd').read_text(encoding='utf8')
    campus=(ROOT/'scripts/campus/world/campus_world.gd').read_text(encoding='utf8')
    patch=(ROOT/'scripts/campus/presentation/decor/lab_floor_coplanar.patch').read_text(encoding='utf8')
    assert '_build_environment()' in game and 'campus=preload("res://scenes/campus/Campus.tscn").instantiate()' in game
    assert 'box(root,center+Vector3(0,-.12,0),Vector3(size.x,.24,size.z)' in campus
    assert '_box(self, Vector3(0, -0.04, 0), Vector3(25, 0.08, 17)' in equipment
    assert '-\t_box(self, Vector3(0, -0.04, 0)' in patch
    original_top=-.04+.08/2
    candidate_top=-.14+.08/2
    shell_top=-.12+.24/2
    assert original_top==shell_top==0 and candidate_top<=shell_top-.02
    # Shared collision is solely the shell: fallback _box creates MeshInstance3D.
    assert 'func _box(parent: Node3D' in equipment and 'MeshInstance3D.new()' in equipment
    for path in ('scripts/game.gd','scripts/equipment_builder.gd','scripts/campus/world/campus_world.gd'):
        print(path,hashlib.sha256((ROOT/path).read_bytes()).hexdigest())
    print('M101 floor: original shared top 0.000m; proposed visual top -0.100m; shell collision unchanged')
if __name__=='__main__':run()
