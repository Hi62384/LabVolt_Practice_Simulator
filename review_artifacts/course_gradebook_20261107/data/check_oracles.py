"""Offline arithmetic and fixture-shape checks; does not execute GDScript."""
from pathlib import Path
import json
import math

root = Path(__file__).resolve().parents[3]
weights = json.loads((root / "assets/campus/courses/grade_weights.json").read_text())["courses"]
for course, policy in weights.items():
    total = sum(policy["lecture"]) + sum(policy["lab"])
    assert math.isclose(total, 100.0, abs_tol=0.001), (course, total)

def points(items):
    earned = sum(score * weight / 100.0 for score, weight in items)
    completed_weight = sum(weight for _, weight in items)
    return earned, earned * 100.0 / completed_weight

assert points([(90, 2)]) == (1.8, 90.0)
assert points([(90, 2), (0, 98)]) == (1.8, 1.8)
assert points([(90, 40), (50, 60)]) == (66.0, 66.0)
assert points([(90, 2), (50, 10)]) == (6.8, 56.666666666666664)

fixture = (Path(__file__).parent / "test_gradebook_view.gd").read_text()
for label in ("90 at 2 percent", "official zero", "profile isolation",
              "course isolation and duplicate slot", "submitted and unavailable",
              "nonfinite weight invalid", "future record metadata tolerated",
              "two same week explicit assessments", "current retake separate from best",
              "old ambiguous history preserved"):
    assert label in fixture, label
selector = (Path(__file__).parent / "attempt_selector.gd").read_text()
assert 'buckets[attempt][key] = value' in selector
assert 'ambiguous_legacy_records' in selector
view = (Path(__file__).parent / "gradebook_view.gd").read_text()
assert 'gradebook_assessment_id' in view and 'sibling_count != 1' in view
print("offline arithmetic/configuration/fixture checks: PASS")
