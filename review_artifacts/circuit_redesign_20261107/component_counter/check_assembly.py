"""Read-only source/contract check for the private store assembly."""
from pathlib import Path
import hashlib
import json

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]

def run():
    packet = json.loads((HERE / "assembly_patches.json").read_text(encoding="utf-8"))
    sources = {}
    for name, expected in packet["source_hashes"].items():
        path = PROJECT / name
        assert hashlib.sha256(path.read_bytes()).hexdigest() == expected, name
        sources[name] = path.read_text(encoding="utf-8")
    for index, patch in enumerate(packet["patches"]):
        name = patch["path"]
        assert hashlib.sha256(patch["old"].encode()).hexdigest() == patch["sha256"], index
        assert sources[name].count(patch["old"]) == 1, (index, name)
        sources[name] = sources[name].replace(patch["old"], patch["new"], 1)
    for item in packet["copies"]:
        assert (PROJECT / item["from"]).is_file(), item
        assert item["to"].startswith("scripts/"), item
    migration = packet["migration_after_m207_verified"]
    assert hashlib.sha256(migration["old"].encode()).hexdigest() == migration["sha256"]
    assert sources[migration["path"]].count(migration["old"]) == 1

    shop = next(x["new"] for x in packet["patches"] if x["old"].startswith("func shop() -> void:"))
    for required in ["profile.get_meta(\"economy_display\"", "shop_adapter.build", "supplies.populate(bundle_mount", "supplies.populate(equipment_mount", "wear.hide()"]:
        assert required in shop, required
    bundle = (HERE / "bundle_module.gd").read_text(encoding="utf-8")
    for callback in ["profile.purchase_bundle", "profile.buy_box", "profile.buy_analyzer", "profile.upgrade_capacity"]:
        assert callback in bundle, callback
    panel = (HERE / "store_panel.gd").read_text(encoding="utf-8")
    for required in ["GridContainer.new()", "OptionButton.new()", "_thumbnail(Visual.icon(entry))", "state.selected_id=\"\"", "purchase_requested.emit(request_id,intent)", "card_counts[id].text="]:
        assert required in panel, required
    clothing = sources["scripts/campus_integration.gd"]
    for callback in ["profile.buy_cosmetic", 'authority_submit.call("cosmetic",request.args)', "wear_settings(id,profile.data)", "save_character(selected,config)", "accept_legacy_receipt(result"]:
        assert callback in clothing, callback
    assert 'page not in ["shop","trade"]' in sources["scripts/shop_room.gd"]
    print("PASS: ordered preimages, private resources, real purchase/receipt/wear callbacks, M102 shop/trade route")

if __name__ == "__main__":
    run()

