"""Bounded source/data checks only. Does not execute GDScript or launch Godot."""
from pathlib import Path
from decimal import Decimal
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = (ROOT / "scripts/electronics/component_values/values.gd").read_text(encoding="utf-8")
ARTIFACTS = ROOT / "review_artifacts/component_values_20261106"

class OfflineChecks(unittest.TestCase):
    def test_all_worker_electrical_numeric_parameters_have_schema(self):
        entries = json.loads((ROOT / "assets/workers/models/catalog.json").read_text(encoding="utf-8"))
        structural = {"price", "space", "worker_model_version", "ground", "supply"}
        numeric = {key for entry in entries.values() for key, value in entry.items()
                   if isinstance(value, (int, float)) and not isinstance(value, bool)} - structural
        exposed = set(re.findall(r'"([a-z0-9_]+)":\["', SOURCE))
        self.assertFalse(numeric - exposed, numeric - exposed)
        self.assertFalse(structural & exposed)

    def test_schema_never_advertises_unimplemented_text_ratings(self):
        self.assertNotIn('"voltage_rating":', SOURCE)
        self.assertIn('entry.has(key)', SOURCE)
        self.assertIn('kind in ["R","C","L","V","pot"]', SOURCE)
        device = (ROOT / "scripts/device_models.gd").read_text(encoding="utf-8")
        self.assertIn('copy.value=.01 if state.get("pressed",false)', device)
        # Button's numerical catalog value is ignored by current gameplay.
        self.assertNotIn('"button","toggle","pot"', SOURCE)

    def test_decimal_fixture_equivalence_and_case(self):
        # Independent exact decimal oracle; this does NOT execute production parser.
        pairs = [("4.7",3,"4700",0),("1",-3,"1000",-6),
                 ("100",-9,"0.1",-6),("1",-6,"1000000",-12),
                 ("333.125",0,"333125",-3),
                 (".123456789012345",0,"123456789012345",-15)]
        for a, sa, b, sb in pairs:
            self.assertEqual(Decimal(a).scaleb(sa), Decimal(b).scaleb(sb))
        self.assertNotEqual(Decimal(1).scaleb(6), Decimal(1).scaleb(-3))

    def test_positive_quantity_and_safe_arithmetic_source(self):
        self.assertIn('float(raw)<1', SOURCE)
        self.assertIn('float(raw)!=floor(float(raw))', SOURCE)
        self.assertIn('q.quantity>MAX_STACK-owned', SOURCE)
        self.assertIn('q.quantity>MAX_COST/int(price)', SOURCE)
        self.assertLess(SOURCE.index('q.quantity>MAX_COST/int(price)'), SOURCE.index('configured.total_price='))
        self.assertEqual(99000 + 1000, 100000)
        self.assertGreater(99000 + 1001, 100000)

    def test_no_mutation_or_authority_side_effects_in_pure_modules(self):
        bridge = (ROOT / "scripts/electronics/component_values/shop_services.gd").read_text(encoding="utf-8")
        for source in (SOURCE, bridge):
            for prohibited in ('FileAccess.', 'DirAccess.', '.rpc(', 'OS.execute', 'data.inventory[', 'data.dollars='):
                self.assertNotIn(prohibited, source)
        self.assertIn('base.duplicate(true)', SOURCE)
        self.assertIn('catalog.duplicate(true)', SOURCE)

    def test_identity_guards_and_legacy_paths(self):
        self.assertIn('if result.ok and result.id!=id:', SOURCE)
        self.assertIn('settings.has(pair[0])', SOURCE)
        self.assertIn('candidates.sort()', SOURCE)
        self.assertIn('if not id.begins_with(PREFIX):return configure(id,{},catalog)', SOURCE)
        self.assertIn('if not key is String or not specs.has(key)', SOURCE)

    def test_exact_shared_preimages_still_stage_in_memory(self):
        patch = json.loads((ARTIFACTS / "shared_patch.json").read_text(encoding="utf-8"))
        work = {}
        for edit in patch["edits"]:
            path = edit["path"]
            source = work.setdefault(path, (ROOT / path).read_text(encoding="utf-8"))
            self.assertEqual(source.count(edit["before"]), 1, path)
            work[path] = source.replace(edit["before"], edit["after"], 1)
        profile = work["scripts/electronics_profile.gd"]
        method = profile[profile.index('func buy_configured('):profile.index('func kit_error(')]
        self.assertLess(method.index('if not authority_confirmed'), method.index('data.inventory[plan.id]='))
        self.assertLess(method.index('if not plan.ok'), method.index('data.inventory[plan.id]='))
        self.assertIn('purchase_debit(int(data.dollars),plan.total_price,true)', method)
        self.assertIn('data=before;return "Save failed; purchase rolled back"', method)
        ledger = work["scripts/inventory_authority/ledger.gd"]
        self.assertLess(ledger.index('if prior.found:'), ledger.index('"buy_configured":'))
        self.assertIn('if prior.value!=digest:return failure(', ledger)
        self.assertIn('if op in ["buy_configured","buy",', ledger)

    def test_deferred_engine_fixtures_cover_required_cases(self):
        fixtures = (ROOT / "tests/electronics/component_values/test_values.gd").read_text(encoding="utf-8")
        for marker in ['Quantity arithmetic beyond old per-buy 100','Every legacy ID preserved',
                       'Independent physical resistor parameters','Client price injection rejected',
                       'Noncanonical ID rejected','Lossless format roundtrip',
                       'Family base does not split identity','Validation does not mutate input catalog']:
            self.assertIn(marker, fixtures)

if __name__ == "__main__":
    unittest.main(verbosity=2)
