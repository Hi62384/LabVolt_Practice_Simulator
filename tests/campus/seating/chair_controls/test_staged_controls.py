"""Source-only contracts for the staged chair change; Godot playtest remains required."""
from pathlib import Path
import hashlib
import json
import math
import unittest

ROOT = Path(__file__).resolve().parents[4]
STAGED = ROOT / "review_artifacts/chair_controls_20261106"


class ChairControlStaging(unittest.TestCase):
    def test_patch_preimages_still_match(self):
        for entry in json.loads((STAGED / "preimages.json").read_text(encoding="utf-8")):
            actual = hashlib.sha256((ROOT / entry["path"]).read_bytes()).hexdigest()
            self.assertEqual(actual, entry["preimage_sha256"], entry["path"])

    def test_relative_limit_and_mode_transitions(self):
        for chair in [-2.4, 0.0, 2.8]:
            head = 0.0
            turn = chair
            head = max(-math.pi / 2, min(math.pi / 2, head + 7.0))
            self.assertAlmostEqual((chair + head) - chair, math.pi / 2)
            turn += 0.35  # Ctrl turns chair while head offset stays fixed.
            self.assertAlmostEqual(head, math.pi / 2)
            self.assertAlmostEqual((turn + head) - turn, math.pi / 2)
            head = max(-math.pi / 2, min(math.pi / 2, head - 0.2))
            self.assertAlmostEqual(head, math.pi / 2 - 0.2)

    def test_existing_pitch_focus_and_pose_path(self):
        player = (STAGED / "scripts__first_person.gd.patch").read_text(encoding="utf-8")
        game = (ROOT / "scripts/game.gd").read_text(encoding="utf-8")
        self.assertIn('pitch_target = clampf(pitch_target-relative.y*sensitivity,-1.46,1.46)', player)
        self.assertIn('if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:', game)
        self.assertIn('"yaw":player.rotation.y', game)
        self.assertIn('seated_look.world_yaw(seated.swivel.rotation.y)', player)
        self.assertIn('yaw_target=seated_look.leave(seated.swivel.rotation.y)', player)

    def test_authority_and_safe_exit_contract(self):
        game = (ROOT / "scripts/game.gd").read_text(encoding="utf-8")
        game_patch = (STAGED / "scripts__game.gd.patch").read_text(encoding="utf-8")
        player_patch = (STAGED / "scripts__first_person.gd.patch").read_text(encoding="utf-8")
        self.assertIn('_accept_chair_input(multiplayer.get_remote_sender_id(),index,wish,yaw)', game)
        self.assertIn('if chair.occupant==peer:', game)
        self.assertIn('+\t\t\t\tchair_input_times[peer]=Time.get_ticks_msec()', game_patch)
        self.assertIn('floor_hit.normal.dot(Vector3.UP)<0.7', player_patch)
        self.assertIn('SafeRecovery.is_known_walkable(destination)', player_patch)
        self.assertLess(player_patch.index('if get_world_3d().direct_space_state.intersect_shape(query,8).is_empty():'),
                        player_patch.index('seated.rider=null', player_patch.index('if get_world_3d().direct_space_state.intersect_shape(query,8).is_empty():')))


if __name__ == "__main__":
    unittest.main()
