import unittest
from unittest.mock import patch
import admission_v3 as a

class Strict(unittest.TestCase):
    def test_missing_publication_rejected(self):
        for value in [None,{}, {'durable':True,'sha256':'a'*64,'path':'elsewhere'}]:
            with self.assertRaises(ValueError):a.receipt('parser',value)
    def test_boolean_job_counts_rejected(self):
        with patch.object(a.v2,'verify_frozen_package',return_value={'total_engine_jobs':1}):
            for key in ['total_engine_jobs','per_job_process_limit']:
                row=dict(total_engine_jobs=1,per_job_process_limit=1);row[key]=True
                with self.assertRaises(ValueError):a.validate('parser',row)
    def test_missing_parser_cleanup_rejected(self):
        with self.assertRaises(ValueError):a.v2.validate_result('parser',{})
    def test_unbounded_and_invalid_context_rejected(self):
        for key,bad in [('request_id',''),('request_id','x'*257),('request_sha256','bad'),('profile_sha256',False),('assessment_id',True),('paper_id',True),('owner_peer',True)]:
            ctx=dict(request_id='r',request_sha256='a'*64,profile_sha256='b'*64,assessment_id='attempt',paper_id=1,owner_peer=2,course='MTH147',op='submit');ctx[key]=bad
            with self.assertRaises(ValueError):a.v2.validate_request_and_privacy('solo',dict(request_context=ctx))

if __name__=='__main__':unittest.main()
