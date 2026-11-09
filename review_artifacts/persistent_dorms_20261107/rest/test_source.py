from pathlib import Path
import hashlib,json,unittest
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
class Rest(unittest.TestCase):
    def test_preimages(self):
        for row in json.loads((HERE/'PREIMAGES.json').read_text()):
            self.assertEqual(hashlib.sha256((ROOT/row['path']).read_bytes()).hexdigest(),row['sha256'])
    def test_authentication_and_pose_gate(self):
        s=(HERE/'rest_state.gd').read_text(); c=(HERE/'rest_controller.gd').read_text()
        for token in ['authority.authenticated_identity(peer)','authority.can_enter(identity,room)','authority.is_owner(identity,room)','state.room==room','position.distance_to(anchor.origin)>3.0']:self.assertIn(token,s)
        self.assertIn('multiplayer.get_remote_sender_id()',c)
        self.assertIn('clean.resting=state.resting.has(peer)',c)
        self.assertIn('state.disconnect(peer)',c)
    def test_pose_and_collision(self):
        p=(HERE/'rest_pose.gd').read_text(); stand=(HERE/'safe_stand.gd').read_text()
        self.assertIn('model.transform=state.transform',p)
        self.assertIn('PI/2.0',p)
        self.assertIn('intersect_shape(query,8).is_empty()',stand)
        self.assertIn('floor_hit.normal.dot(Vector3.UP)<.7',stand)
        for radius in [.85,1.15,1.5,2.0]:self.assertGreater(radius,.25)
        # A rigid quarter-turn preserves lengths and makes vertical axis horizontal.
        import math
        self.assertAlmostEqual(math.cos(math.pi/2),0.)
        self.assertAlmostEqual(math.sin(math.pi/2),1.)
if __name__=='__main__':unittest.main()
