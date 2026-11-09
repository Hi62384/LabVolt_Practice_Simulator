"""Offline geometric admission for staged paving depth fix."""
from pathlib import Path
import hashlib
root=Path(__file__).resolve().parents[4]
path=root/'scripts/campus/world/campus_world.gd'
source=path.read_text(encoding='utf8')
patch=(root/'scripts/campus/presentation/decor/hall_paving_depth.patch').read_text(encoding='utf8')
assert 'Vector3(13,-.12,21.5),Vector3(6,.24,93)' in source
assert 'Vector3(8+(i%10),.015,-23+(i/10)*2)' in source
assert 'Vector3(8+(i%10),.015,-23+(i/10)*2)' in patch
hall_top=-.12+.24/2
old_tile_top=-.01+.02/2
new_tile_bottom=.015-.02/2
assert old_tile_top==hall_top==0 and new_tile_bottom>hall_top
overlap=[i for i in range(20) if 10<8+i%10+.45 and 8+i%10-.45<16 and -25<-23+(i//10)*2+.45]
assert overlap
print('overlapping paving tiles:',overlap,'old shared top:',old_tile_top,'new bottom:',new_tile_bottom)
print('campus source sha256:',hashlib.sha256(path.read_bytes()).hexdigest())
