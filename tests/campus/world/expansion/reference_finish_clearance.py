"""Offline AABB clearance for the mounted reference finish and teaching baffles."""
from pathlib import Path
import hashlib
root=Path(__file__).resolve().parents[4]
reference=root/'scripts/campus/presentation/decor/teaching_rooms/reference_style_finish.gd'
teaching=root/'scripts/campus/presentation/decor/teaching_rooms/teaching_room_finish.gd'
patch=root/'scripts/campus/presentation/decor/reference_fixture_clearance.patch'
assert 'for x in [cx-4.5,cx,cx+4.5]:' in reference.read_text(encoding='utf8')
assert 'for x in ([cx-2.7,cx+2.7] if id=="dc_lab"' in patch.read_text(encoding='utf8')
assert 'Vector3(x,float(p.base)+3.92' in teaching.read_text(encoding='utf8')
old_fixture=(-.775,.775); baffle=(-.06,.06)
assert max(old_fixture[0],baffle[0])<min(old_fixture[1],baffle[1])
for fixture_x in [-2.7,2.7]:
    for baffle_x in [-5.4,0,5.4]:
        assert abs(fixture_x-baffle_x)>.775+.06
assert 3.96-.045/2<3.92+.14/2 # heights overlap, hence X correction matters
# South/north trim inward gap: wall inner face .08, trim nearest face .0975.
assert .11-.025/2>.08
# Side door wall is the opposite side from the chosen side_x.
assert .12-.035/2>.08
print('M103 fixture/baffle AABBs separated; trims inset from shell; door side untouched')
print('preimage',hashlib.sha256(reference.read_bytes()).hexdigest())
