from pathlib import Path
import re

root = Path(__file__).resolve().parents[3]
profile = (root / 'scripts/electronics_profile.gd').read_text(encoding='utf-8')
ui = (root / 'scripts/electronics_ui.gd').read_text(encoding='utf-8')
candidate = (Path(__file__).parent / 'legacy_cosmetic_adapter.gd').read_text(encoding='utf-8')
expected = {'copper_coat': 35, 'gold_safety': 25, 'blue_gloves': 20, 'copper_hat': 30}
for key, price in expected.items():
    assert re.search(r'"' + key + r'":\{"name":"[^"]+","price":' + str(price), profile), key
assert 'if id in data.get("cosmetics",[]):return "Already owned"' in profile
assert 'data.cosmetics.append(id);data.dollars=debit.next_balance' in profile
assert 'config.merge(cosmetic.settings,true)' in ui
assert 'game.characters.save_character' in ui
assert '"op": "cosmetic"' in candidate and 'Profile.COSMETICS[id].settings' in candidate
section = (Path(__file__).parent / 'legacy_wear_section.gd').read_text(encoding='utf-8')
mount = (Path(__file__).parent / 'MOUNT_PATCH.md').read_text(encoding='utf-8')
integration = (root / 'scripts/campus_integration.gd').read_text(encoding='utf-8')
assert 'clothing_panel.open_profile(profile.data' in integration
assert 'game.campus.registry.locate(game.player.global_position)=="clothing_store"' in integration
for seam in ['Catalog.rows(profile)', 'UI.card(', 'purchase_requested.emit(request)', 'wear_requested.emit(id)', 'accept_receipt(result: Dictionary, snapshot: Dictionary)']:
    assert seam in section, seam
for seam in ['authority_submit.call("cosmetic", request.args)', 'profile.buy_cosmetic(request.args[0])', 'game.characters.save_character(selected, config)', 'op == "cosmetic"']:
    assert seam in mount, seam
print('verified 4 exact products, prices, ownership, reachable cards, purchase receipt and wear hooks')
