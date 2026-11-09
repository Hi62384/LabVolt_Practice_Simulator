"""Bounded arithmetic checks for the proposed M101 geometry patch, no engine."""
from pathlib import Path
import hashlib

ROOT=Path(__file__).resolve().parents[3]

def main():
    scale=.68; origin=.75; tabletop=.7+.14/2
    # Station modules remain unchanged; shorten only backing/post buried ends.
    for old_center,old_height,new_center,new_height in [(2.23,4.60,2.28,4.50),(2.26,4.76,2.335,4.61)]:
        old_bottom=origin+scale*(old_center-old_height/2)
        new_bottom=origin+scale*(new_center-new_height/2)
        assert old_bottom<tabletop
        assert new_bottom>=tabletop-1e-9
        assert abs((old_center+old_height/2)-(new_center+new_height/2))<1e-9
        print(f"rack end: {old_bottom:.4f} -> {new_bottom:.4f} m; tabletop {tabletop:.4f}; original top preserved")
    board=(-2.85,2.85)
    for x in [-8,-5,5]:
        cabinet=(x-.75,x+.75)
        assert cabinet[1]<board[0] or cabinet[0]>board[1]
        assert -9.92<cabinet[0]<cabinet[1]<9.92
    patch=(ROOT/'scripts/campus/presentation/decor/m101_geometry.patch').read_text(encoding='utf8')
    source=(ROOT/'scripts/equipment_builder.gd').read_text(encoding='utf8')
    assert 'for xpos in [-3.29,3.29]:' in source, 'source changed: rebase patch'
    assert origin+scale*(.055-.048/2)>tabletop
    for old in [line[1:] for line in patch.splitlines() if line.startswith('-\t')]:
        assert old in source or old in (ROOT/'scripts/room_finish.gd').read_text(encoding='utf8'), f'preimage no longer matches: {old}'
    print('cabinet bounds clear whiteboard; patch preimages match current source')
    for relative in ['scripts/equipment_builder.gd','scripts/room_finish.gd','scripts/campus/presentation/decor/m101_geometry.patch']:
        print(relative,hashlib.sha256((ROOT/relative).read_bytes()).hexdigest())

if __name__=='__main__':main()
