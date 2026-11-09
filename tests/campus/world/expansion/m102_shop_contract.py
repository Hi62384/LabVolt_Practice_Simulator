"""Bounded source contract for staged M102 migration; no engine or user data."""
from pathlib import Path
import hashlib
root=Path(__file__).resolve().parents[4]
source=(root/'scripts/shop_room.gd').read_text(encoding='utf8')
candidate=(root/'scripts/campus/presentation/decor/component_shop_fitout_candidate.gd').read_text(encoding='utf8')
patch=(root/'scripts/campus/presentation/decor/m102_shop_only.patch').read_text(encoding='utf8')
assert 'game.electronics.open(page)' in source
assert 'physical_stations.trade.position=Vector3(30,0,5)' in patch
assert '"shop","Component counter"' in candidate and '"trade","Player trading counter"' in candidate
assert 'Label3D' not in candidate and 'billboard' not in candidate
for unwanted in ['KIT WORKSHOP','CUSTOM CIRCUITS','LOADOUT & NOTES','CAMPUS / RETURN','ELECTRONICS WORKSHOP']:
    assert ('+'+unwanted) not in patch
print('M102 staged shop/trade destinations, no replacement billboard, legacy rows removed')
for rel in ['scripts/shop_room.gd','scripts/campus/presentation/decor/component_shop_fitout_candidate.gd']:
    print(rel,hashlib.sha256((root/rel).read_bytes()).hexdigest())
