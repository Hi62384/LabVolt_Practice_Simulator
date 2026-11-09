"""Bounded offline asset/authority-boundary checks; never launches Godot."""
from pathlib import Path
import hashlib
import json
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = ROOT / "scripts/electronics/component_shop_ui"
ASSETS = ROOT / "assets/electronics/component_shop_ui"

def run():
    icons = list(ASSETS.glob("*.svg"))
    assert len(icons) >= 16
    assert len({hashlib.sha256(p.read_bytes()).hexdigest() for p in icons}) == len(icons)
    for path in icons:
        svg = ET.parse(path).getroot()
        assert svg.attrib["viewBox"] == "0 0 64 64"
        assert not any(node.tag.endswith(("image", "script", "text")) for node in svg.iter())
    tokens = (ROOT / "scripts/ui/design_system/tokens.gd").read_text(encoding="utf-8")
    def rgb(value):
        return [int(value[i:i+2], 16)/255 for i in (0, 2, 4)]
    def luminance(color):
        channels = [c/12.92 if c <= .04045 else ((c+.055)/1.055)**2.4 for c in color]
        return sum(c*w for c, w in zip(channels, (.2126, .7152, .0722)))
    surface = rgb(re.search(r'SURFACE := Color\("([0-9a-f]{6})"\)', tokens)[1])
    for value in re.findall(r'return Color\("([0-9a-f]{6})"\)', tokens):
        # Exact shared-token icon tile blend used by catalog_presentation.gd.
        background = [a*.17+b*.83 for a,b in zip(rgb(value), surface)]
        assert (luminance(rgb("f3f7fb"))+.05)/(luminance(background)+.05) >= 4.5
    for path in SCRIPTS.glob("*.gd"):
        text = path.read_text(encoding="utf-8")
        # Shop is a read-only presentation client of the existing purchase API.
        assert not re.search(r"FileAccess|DirAccess|\.rpc|\.dollars\s*[-+]?=|\.inventory\s*\[.*?\]\s*=", text), path
        for resource in re.findall(r'(?:preload|load)\("res://([^"\n]+)"\)', text):
            assert (ROOT / resource).is_file(), resource
    patch_doc = json.loads((SCRIPTS / "shared_hookups.json").read_text(encoding="utf-8"))
    for patch in patch_doc["patches"]:
        assert hashlib.sha256(patch["old"].encode()).hexdigest() == patch["preimage_sha256"]
        # These checks are intentionally strict. A changed shared file requires
        # integrator reconciliation; the checker never retries or applies it.
        source = (ROOT / patch["path"]).read_text(encoding="utf-8")
        assert source.count(patch["old"]) == 1, f"Stale/ambiguous preimage: {patch['path']}"
    print(f"PASS: {len(icons)} unique standalone vector icons, resource references, no shop persistence/RPC writes, {len(patch_doc['patches'])} unique staged hookup preimages")

if __name__ == "__main__":
    run()
