import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
contract = json.loads((ROOT / "assets/campus/clothing_store/room_contract.json").read_text())
low, high = contract["local_bounds_min"], contract["local_bounds_max"]
assert all(low[i] < high[i] for i in range(3))
for name, point in contract["interaction_anchors"].items():
    assert all(low[i] <= point[i] <= high[i] for i in range(3)), name

seen = set()
count = 0
for resource in contract["catalog_sources"]:
    path = ROOT / resource.removeprefix("res://")
    payload = json.loads(path.read_text())
    for item in payload["items"]:
        assert item["id"] not in seen, item["id"]
        seen.add(item["id"])
        assert isinstance(item["price"], int) and item["price"] >= 0
        assert (ROOT / item["scene"].removeprefix("res://")).is_file()
        assert (ROOT / item["thumbnail"].removeprefix("res://")).is_file()
        count += 1
assert count >= 20
room_source = (ROOT / "scripts/campus/facilities/clothing_store/room_builder.gd").read_text()
assert 'label in ["Checkout", "RackBase", "BenchSeat", "BenchBack"]' in room_source
assert 'label == "Plinth"' in room_source
# Full local footprints; mounted at (2,5,49) with +90 degrees around Y.
solids = [(2.9, 0.62, side * 5.8, z) for side in (-1, 1) for z in (-4.7, -1.8, 1.1)]
solids += [(4.8, 1.25, 5.3, 5.9), (3.4, 1.2, -3.2, 5.8)]
solids += [(2.1, 2.1, x, -5.6) for x in (-2.3, 2.3)]
for width, depth, x, z in solids:
    assert -8.9 < x - width / 2 and x + width / 2 < 8.9
    assert -7.9 < z - depth / 2 and z + depth / 2 < 7.9
    # A clear 1.25m-radius route from the door to the central display aisle.
    if z + depth / 2 > -4.0:
        assert x + width / 2 <= -1.25 or x - width / 2 >= 1.25
for name in ("catalog", "mirror", "checkout"):
    x, _, z = contract["interaction_anchors"][name]
    assert all(not (abs(x - cx) < width / 2 + .3 and abs(z - cz) < depth / 2 + .3)
               for width, depth, cx, cz in solids), name
assert [2 + contract["door_local"][2], 5, 49 - contract["door_local"][0]] == [10, 5, 49]
print(f"validated {count} store items and {len(contract['interaction_anchors'])} interaction anchors")
