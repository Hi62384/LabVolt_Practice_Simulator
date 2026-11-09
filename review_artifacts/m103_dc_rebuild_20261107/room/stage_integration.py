"""Stage an exact-preimage M103 mount patch; never edit production here."""
from pathlib import Path
import difflib
import hashlib
import json

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
TARGET = ROOT / "scripts/campus_integration.gd"
old = TARGET.read_bytes()
source = old.decode("utf-8")
before = '''\troom_finish_results.teaching=teaching_finish.mount_approved(game.campus,game.campus.registry,["dc_lab","elm253_lecture","ety155_lecture","computer"])'''
after = '''\troom_finish_results.teaching=teaching_finish.mount_approved(game.campus,game.campus.registry,["elm253_lecture","ety155_lecture","computer"])'''
assert source.count(before) == 1
source = source.replace(before, after)
before = '''\tfor id in ["shop","dc_lab","elm253_lecture","ety155_lecture","computer"]:
\t\troom_finish_results.reference[id]=reference_finish.mount(id,game.campus,game.campus.registry)'''
after = '''\tfor id in ["shop","elm253_lecture","ety155_lecture","computer"]:
\t\troom_finish_results.reference[id]=reference_finish.mount(id,game.campus,game.campus.registry)
\tvar m103_finish=preload("res://review_artifacts/m103_dc_rebuild_20261107/room/m103_room_finish.gd").new()
\tadd_child(m103_finish)
\troom_finish_results.m103=m103_finish.mount(game.campus,game.campus.registry)'''
assert source.count(before) == 1
source = source.replace(before, after)
new = source.encode("utf-8")
(HERE / "campus_integration.gd.preimage").write_bytes(old)
(HERE / "campus_integration.gd.proposed").write_bytes(new)
(HERE / "campus_integration.gd.patch").write_text("".join(difflib.unified_diff(
    old.decode("utf-8").splitlines(keepends=True),
    new.decode("utf-8").splitlines(keepends=True),
    fromfile="a/scripts/campus_integration.gd",
    tofile="b/scripts/campus_integration.gd")), encoding="utf-8")
(HERE / "integration_manifest.json").write_text(json.dumps({
    "target":"scripts/campus_integration.gd",
    "preimage_sha256":hashlib.sha256(old).hexdigest(),
    "proposed_sha256":hashlib.sha256(new).hexdigest(),
    "candidate":"review_artifacts/m103_dc_rebuild_20261107/room/m103_room_finish.gd",
    "requires_exact_preimage":True,
},indent=2)+"\n", encoding="utf-8")
print("Staged M103 mount patch", hashlib.sha256(old).hexdigest())
