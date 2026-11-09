import hashlib,json,sys,unittest
from pathlib import Path
B=Path(r'C:\Users\User1\Documents\Codex\2026-11-05\task-6\eight_participants_v11_current');sys.path.insert(0,str(B));sys.dont_write_bytecode=True
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
class Packet(unittest.TestCase):
 def test_bindings(self):
  from path_contract import validate_paths
  from admission_contract import envelope
  from run_j import inventory
  commands=json.loads((B/'COMMANDS.json').read_text());self.assertEqual(len(commands),5)
  previous=None
  for c in commands:
   p=json.loads(Path(c['argv'][4]).read_text());self.assertEqual(sha(c['argv'][4]),c['plan_sha256']);self.assertTrue(validate_paths(p,B));self.assertTrue(envelope(p))
   self.assertFalse(Path(p['output']).exists());self.assertFalse(Path(p['required_root_grant']).exists())
   for path,digest in p['bound_files'].items():self.assertEqual(sha(path),digest)
   inventory(Path(p['project']),json.loads(Path(p['source_cache_lock']).read_text()),Path(p['fixture_overlay']))
   if p['scenario']=='lifecycle':self.assertEqual(p['previous_name'],previous);previous=p['name']
 def test_zero_earnings_and_event_required(self):
  from evidence import zero_earnings,EvidenceError
  before={'dollars':100};after={'dollars':100,'assessment_id':'a','gradebook':{'g':{'id':'g','lesson':False,'course_id':'MTH147','assessment_id':'a'}},'reward_ids':{'g':0}}
  zero_earnings(before,after,'MTH147')
  for field,value in [('dollars',101),('reward_ids',{})]:
   bad=dict(after);bad[field]=value
   with self.assertRaises(EvidenceError):zero_earnings(before,bad,'MTH147')
if __name__=='__main__':unittest.main(verbosity=2)
