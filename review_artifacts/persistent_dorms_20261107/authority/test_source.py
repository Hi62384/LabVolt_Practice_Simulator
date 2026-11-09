"""Source/preimage/geometry checks only. Does not parse or execute GDScript."""
from pathlib import Path
import hashlib,json,re,unittest
P=Path(__file__).resolve().parent
ROOT=P.parents[2]
C=P/'candidate'
def read(path):return (C/path).read_text(encoding='utf-8')
class SourceChecks(unittest.TestCase):
    def test_current_preimages_and_candidate_hashes(self):
        for path,entry in json.loads((P/'PATCHES.json').read_text()).items():
            target=ROOT/path
            self.assertEqual(hashlib.sha256(target.read_bytes()).hexdigest() if target.exists() else None,entry['preimage_sha256'],path)
            self.assertEqual(hashlib.sha256((C/path).read_bytes()).hexdigest(),entry['candidate_sha256'],path)
    def test_resource_paths_exist(self):
        for file in C.rglob('*.gd'):
            for resource in re.findall(r'(?:preload|load)\("res://([^"\n]+)"\)',file.read_text(encoding='utf-8')):
                self.assertTrue((C/resource).exists() or (ROOT/resource).exists(),(file,resource))
    def test_bind_migrates_before_binding_and_snapshot(self):
        source=read('scripts/inventory_authority/ledger.gd')
        bind=source.split('func bind(',1)[1].split('func unbind',1)[0]
        self.assertLess(bind.index('Dorm.migrate'),bind.index('bindings[peer]=identity'))
        self.assertIn('if not persist(next):return failure("Dorm enrollment save failed")',bind)
        self.assertIn('profile_ready.emit(peer)',read('scripts/inventory_authority/network.gd'))
    def test_replay_precedes_revision_and_single_commit(self):
        s=read('scripts/inventory_authority/ledger.gd').split('func transact(',1)[1].split('func award(',1)[0]
        self.assertLess(s.index('receipt_history.lookup_op'),s.index('Dorm.apply_intent'))
        self.assertLess(s.index('target.receipts[id]=digest'),s.index('if not persist(next)'))
        self.assertIn('"dorm"',s)
    def test_inventory_reservations(self):
        s=read('scripts/inventory_authority/ledger.gd')
        self.assertIn('Dorm.reserved(p.data,a.deployment)',s)
        self.assertIn('"instance_ids":a.deployment.get("instance_ids",[])+a.profile.get("dorm",{}).get("instances",[])',s)
        self.assertIn('excluded.append_array(source.profile.get("dorm",{}).get("instances",[]))',s)
        self.assertIn('if id not in stored',read('scripts/inventory_authority/component_persistence.gd'))
    def test_projection_allowlist(self):
        s=read('scripts/campus/dorms/authority/persistent_dorm.gd').split('static func public_room',1)[1]
        for private in ['notebook','programs','credential','storage','component_runtime']:
            self.assertNotIn('"'+private+'"',s)
        self.assertIn('valid_customization(customization)',s)
    def test_ready_stable_identity_and_private_desktop(self):
        s=read('scripts/campus/dorms/integration/coordinator.gd')
        self.assertNotIn('"peer:"',s)
        self.assertIn('_ledger().bindings.get(peer',s)
        self.assertIn('profile_ready.connect',s)
        self.assertIn('range(page*32,mini((page+1)*32,ids.size()))',s)
        self.assertIn('game.computers.set_private_owner(station,owner)',s)
        self.assertIn('game.computers.stations[station].anchor=furnished.targets.computer.global_position',s)
        desktop=read('scripts/campus/computers/computer_sessions.gd')
        self.assertIn('str(session.get("identity",""))!=_identity(peer)',desktop)
        self.assertIn('workspace_identities.get(peer,"__unbound__")!=identity',desktop)
        self.assertIn('packet.erase("identity")',desktop)
    def test_migration_preserves_corrupt_source(self):
        s=read('scripts/electronics_profile.gd')
        self.assertIn('original file retained; restore profile before playing',s)
        self.assertIn('if save()!=OK:data=before',s)
        self.assertIn('student_identity.cfg',s)
    def test_room_adapter_actual_apis(self):
        s=read('scripts/campus/dorms/integration/room_adapter.gd')
        self.assertIn('game.get("dorm_interactions").router',s)
        self.assertIn('request_personal_computer',s)
        coordinator=read('scripts/campus/dorms/integration/coordinator.gd')
        self.assertIn('game.dorm_rest.state.register_bed(room,anchor)',coordinator)
        self.assertIn('game._request_chair',coordinator)
        self.assertIn('panel.open_profile(profile.data,null',coordinator)
    def test_source_derived_starter_geometry(self):
        helper=read('scripts/campus/dorms/authority/persistent_dorm.gd')
        points={key:(float(x),float(z)) for key,x,z in re.findall(r'"(\w+)":Vector2\(([-.\d]+),([-.\d]+)\)',helper)}
        rules=read('scripts/campus/dorms/customization/placement_rules.gd')
        sizes={key:(float(x),float(z)) for key,x,z in re.findall(r'"(\w+)":Vector2\(([.\d]+),\s*([.\d]+)\)',rules)}
        self.assertEqual(len(points),12)
        surfaces={'bedside_lamp','desk_lamp','desk_laptop','display'}
        nonsolid={'rug','poster'}
        solids=[]
        def overlap(a,b):return a[0]<b[2] and a[2]>b[0] and a[1]<b[3] and a[3]>b[1]
        for key,(x,z) in points.items():
            w,h=sizes[key];rect=(x-w/2,z-h/2,x+w/2,z+h/2)
            self.assertTrue(rect[0]>=-3.32 and rect[2]<=3.32 and rect[1]>=-5.57 and rect[3]<=5.57,key)
            if key in surfaces|nonsolid:continue
            self.assertFalse(overlap(rect,(-4.55,-1.1,-2.45,1.1)),key+' door')
            self.assertFalse(overlap(rect,(-2.6,-.75,0,.75)),key+' entry path')
            for other,other_rect in solids:self.assertFalse(overlap(rect,other_rect),key+'/'+other)
            solids.append((key,rect))
    def test_no_disconnect_deletion(self):
        coordinator=read('scripts/campus/dorms/integration/coordinator.gd')
        self.assertNotIn('state.accounts.erase',coordinator)
        self.assertNotIn('"dorm").erase',coordinator)
        self.assertIn('occupants.erase(peer)',coordinator)
if __name__=='__main__':unittest.main(verbosity=2)
