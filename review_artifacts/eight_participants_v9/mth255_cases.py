"""MTH255 case specialization for the reviewed classroom Run contract; no launcher."""
import math, re
from fractions import Fraction

NUMBER = r'[-+]?\d+(?:\.\d+)?'

def answers_for(project):
    """Derive answers from displayed givens only, never parameters/answer/rubric."""
    out=[]
    for q in project['questions']:
        prompt=q['prompt']; topic=q['generator_id']
        nums=[float(x) for x in re.findall(NUMBER,prompt)]
        if topic=='j_power':
            assert re.fullmatch(r'Evaluate j\^\(-?\d+\)\. Give real and imaginary components\.',prompt)
            n=int(nums[0]); z=(1,1j,-1,-1j)[n%4]
            answer={'real':float(complex(z).real),'imag':float(complex(z).imag)}
        elif topic=='complex_convert':
            match=re.fullmatch(r'Convert ('+NUMBER+r')\+j\*\(('+NUMBER+r')\) to polar form\. Give nonnegative magnitude and angle in degrees \(5 decimal places\)\.',prompt)
            assert match, prompt
            a,b=map(float,match.groups()); answer={'magnitude':math.hypot(a,b),'angle':math.degrees(math.atan2(b,a))}
            assert q['expected_form']=='polar'
        elif topic=='complex_plot':
            points=re.findall(r'z\d+=('+NUMBER+r')\+j\*\(('+NUMBER+r')\)',prompt)
            assert points and q['input']['kind']=='complex_plane'
            assert q['diagram']['points']==[], 'diagram prefilled target'
            answer={'points':[{'x':float(x),'y':float(y)} for x,y in points]}
        elif topic=='complex_components':
            match=re.search(r'z=\(('+NUMBER+r')\+j\*\(('+NUMBER+r')\)\)\+\(('+NUMBER+r')\+j\*\(('+NUMBER+r')\)\)',prompt)
            assert match,prompt
            a,b,c,d=map(float,match.groups()); x,y=a+c,b+d
            quadrant=0 if x==0 or y==0 else 1 if x>0 and y>0 else 2 if x<0 else 4
            if x<0 and y<0:quadrant=3
            answer={'real':x,'imag':y,'quadrant':quadrant,'argument_defined':int(x!=0 or y!=0)}
        else: raise AssertionError('Unreviewed Main question topic: '+topic)
        out.append(answer)
    assert len(out)==8 and {q['generator_id'] for q in project['questions']}=={'j_power','complex_convert','complex_plot','complex_components'}
    return out

def case_class(base, evidence):
    """Return a Run subclass; approved caller retains grant/backend/start/cleanup ownership."""
    class MTH255Run(base):
        expected={}
        def commands(self,commands):
            # Replace only the inherited placeholder answer command, using each peer's
            # own public question payload. Remote payload is never sent to another peer.
            if commands and all(c.get('op')=='request' and c.get('action',{}).get('op')=='answer' for c in commands.values()):
                plans={}
                for role,c in commands.items():
                    selector=c['selector']; project=self.latest[role]['mth255_public'][selector]
                    plans[role]=answers_for(project)
                    if selector=='official':self.expected[role]=100.0 if role=='host' else 0.0
                result=None
                for index in range(8):
                    batch={}
                    for role,c in commands.items():
                        answer=plans[role][index] if role=='host' else {}
                        batch[role]={'op':'request','selector':c['selector'],'action':{'op':'answer','key':str(index),'value':answer}}
                    result=super().commands(batch)
                return result
            result=super().commands(commands)
            for role,snapshot in self.latest.items():
                for p in snapshot.get('papers',[]):
                    if p['owner']==snapshot['peer'] and p['official'] and p['marked'] and role in self.expected:
                        evidence.need(abs(p['score']-self.expected[role])<1e-8,'independent public-givens mark differs for '+role)
            return result
        def lifecycle(self):
            evidence.need(self.plan['course']=='MTH255' and self.plan['kind']=='lecture','MTH255 lecture only')
            self.expected={}
            super().lifecycle()
            if self.plan['scenario'] in ('solo_save','late'):
                self.commands({'host':{'op':'prepare_room'}})
                self.commands({'host':{'op':'request','selector':'official','action':{'op':'submit'}}})
                self.poll(['host'],lambda:any(p['official'] and p['marked'] for p in self.latest['host']['papers']))
                self.poll(['host'],lambda:any(k.startswith('assessment:') for k in self.latest['host']['reward_ids']))
                before=self.latest['host']
                self.commands({'host':{'op':'request','selector':'official','action':{'op':'submit'}}})
                evidence.exactly_once(before,self.latest['host'],'MTH255')
    return MTH255Run

