"""Bounded source checks only; not a GDScript parser or visual acceptance."""
import hashlib, json, pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[3]
ART = ROOT/'review_artifacts/avatar_body_hooks_20261106'
class Contract(unittest.TestCase):
    def test_shared_preimages_untouched(self):
        for row in json.loads((ART/'PREIMAGES.json').read_text()):
            self.assertEqual(hashlib.sha256((ROOT/row['path']).read_bytes()).hexdigest(),row['sha256'])
    def test_all_missing_fields_consumed(self):
        text = (ROOT/'scripts/avatar_cosmetics/body_deformation/body_fit.gd').read_text()
        for field in ['neck_length','neck_width','torso_length','torso_width','hips','arm_width','leg_width','build']:
            self.assertIn('p.'+field,text)
    def test_preview_export_adapter_hook(self):
        toon = (ART/'toon_character.patch').read_text()
        renderer = (ART/'avatar_renderer.patch').read_text()
        self.assertIn('build(config,modern_body)',toon)
        self.assertIn('BodyDeformation.apply(root,modern_body,c)',toon)
        self.assertIn('Toon.build(legacy,body)',renderer)
        self.assertIn('BodyDeformation.finish(avatar)',renderer)
    def test_legacy_bypass_and_parent_length(self):
        rig=(ROOT/'scripts/avatar_cosmetics/body_deformation/rig_adapter.gd').read_text()
        self.assertIn('if raw.is_empty() or avatar.has_meta(META): return',rig)
        self.assertNotIn('leg.scale =',rig)
        self.assertNotIn('arm.scale =',rig)
        self.assertIn('if not Fit.has_deformation(p): return',rig)
        self.assertIn('delta*rotation',rig)
        self.assertIn('arm.quaternion*old_rest.inverse()',rig)
        self.assertNotIn('func _process',rig)
        self.assertNotIn('func _physics_process',rig)
        toon=(ART/'toon_character.patch').read_text()
        self.assertLess(toon.index('BodyDeformation.apply(root,modern_body,c)'),toon.index('\n \t_animations(root)'))
        renderer=(ART/'avatar_renderer.patch').read_text()
        self.assertIn('var model := render_avatar(state,catalog)',renderer)
if __name__=='__main__': unittest.main()
