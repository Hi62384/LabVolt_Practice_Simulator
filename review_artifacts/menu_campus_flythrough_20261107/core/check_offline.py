"""Read-only integration checks. Run from the project root with Python."""
from pathlib import Path
import hashlib
import json
import math
import re
import runpy
import subprocess

root = Path.cwd()
base = root / "review_artifacts/menu_campus_flythrough_20261107"
core = base / "core"
manifest = json.loads((core / "PREIMAGES.json").read_text())
paths = [str(core / (name.replace("/", "__") + ".patch")) for name in manifest]
subprocess.run(["git", "apply", "--check", *paths], check=True)
patched = {}
for name, record in manifest.items():
    raw = (root / name).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == record["preimage_sha256"], name
    encoding = "utf-8-sig" if raw.startswith(b"\xef\xbb\xbf") else "utf-8"
    source = raw.decode(encoding).replace("\r\n", "\n")
    for hunk in record["anchors"]:
        assert source.count(hunk["before"]) == 1, (name, hunk["before"])
        source = source.replace(hunk["before"], hunk["after"], 1)
    patched[name] = source
    raw_result = source.replace("\n", "\r\n") if b"\r\n" in raw else source
    assert hashlib.sha256(raw_result.encode(encoding)).hexdigest() == record["postimage_sha256"], name

# The visual owner uses exact hunk substitutions without line-number ranges.
# Check their old spans are unique after applying the lifecycle spans.
menu = patched["scripts/front_menu.gd"]
visual = (base / "menu/FRONT_MENU_VISUAL.patch").read_text(encoding="utf-8-sig")
for hunk in re.split(r"(?m)^@@.*\n", visual)[1:]:
    lines = hunk.splitlines()
    before = "\n".join(line[1:] for line in lines if line.startswith(("-", " "))) + "\n"
    assert menu.count(before) == 1, before
    after = "\n".join(line[1:] for line in lines if line.startswith(("+", " "))) + "\n"
    menu = menu.replace(before, after, 1)
assert "preview_camera" not in menu
assert menu.count("func _academic_menu_catalog") == 1
assert "COLLEGE" in menu.replace(" ", "") and "Learn. Explore. Experiment." in menu
assert menu.index("game.menu_campus.hold(true)") < menu.index("game.session.join_game")
assert "if not game.session.online:\n\t\t\tjoining=false" in menu
assert "elif game.session.roster.has(multiplayer.get_unique_id())" in menu
game = patched["scripts/game.gd"]
assert game.index("lab_challenges.build(self)") < game.index("menu_campus.show_menu()")
assert game.index("menu_campus.enter_game()") < game.index("front.entered()")

# Resolve the candidate source files as they would be installed.
new_files = {p.relative_to(core / "new").as_posix(): p for p in (core / "new").rglob("*.gd")}
new_files["scripts/campus/presentation/menu_flythrough/routes.gd"] = base / "routes/routes.gd"
for source in [game, *[p.read_text(encoding="utf-8-sig") for p in new_files.values()]]:
    for ref in re.findall(r'preload\("res://([^"]+)"\)', source):
        assert ref in new_files or (root / ref).is_file(), ref

generator = runpy.run_path(str(base / "routes/build_routes.py"))
assert not generator["validate"](), "Route owner geometry audit failed"
rows = json.loads((base / "routes/routes.json").read_text())["routes"]
catalog = new_files["scripts/campus/presentation/menu_flythrough/routes.gd"].read_text(encoding="utf-8-sig")
assert rows == generator["routes"], "Route JSON differs from the audited generator"
assert re.findall(r'"id": "([^"]+)"', catalog) == [row["id"] for row in rows]
registry = json.loads((root / "assets/campus/world/room_registry.json").read_text(encoding="utf-8-sig"))
room_ids = {room["id"] for room in registry["rooms"]}
assert set(re.findall(r'"location": "([^"]+)"', catalog)) <= room_ids | {"exterior", "circulation"}
assert len(rows) == len({row["id"] for row in rows})
for pin_list in re.findall(r'"rooms": PackedStringArray\(\[([^]]*)\]\)', catalog):
    assert set(re.findall(r'"([^"]+)"', pin_list)) <= room_ids

# Compare the source controller's easing formula at the ramp boundaries and
# check normalized progress across each route's chord-length duration.
def travel(seconds, duration):
    ramp = min(2.0, duration * 0.25)
    divisor = duration - ramp
    if seconds < ramp:
        return 0.5 * seconds * seconds / (ramp * divisor)
    left = duration - seconds
    if left < ramp:
        return 1.0 - 0.5 * left * left / (ramp * divisor)
    return (seconds - 0.5 * ramp) / divisor

for row in rows:
    points = row["points"]
    duration = sum(math.dist(a, b) for a, b in zip(points, points[1:])) / row["speed_mps"]
    assert duration > 3.0, row["id"]
    progress = [travel(duration * index / 1000, duration) for index in range(1001)]
    assert progress[0] == 0 and progress[-1] == 1
    assert all(a < b for a, b in zip(progress, progress[1:])), row["id"]

print(f"Verified {sum(len(item['anchors']) for item in manifest.values())} hook anchors, visual patch composition, preload paths, {len(rows)} route IDs and easing/source envelopes.")

