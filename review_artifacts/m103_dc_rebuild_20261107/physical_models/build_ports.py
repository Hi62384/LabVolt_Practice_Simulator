"""Authoritative fixed M103 port geometry, all device-local metres."""
from pathlib import Path
import json

OUT=Path(__file__).resolve().parent
devices={
 'psu': {'origin':[-1.50,1.258,-.10], 'size':[1.46,.70,.53], 'front_z':0.0},
 'meter':{'origin':[0,1.078,-.18], 'size':[1.05,.34,.40], 'front_z':0.0},
 'generator':{'origin':[0,1.446,-.18], 'size':[1.05,.34,.44], 'front_z':0.0},
 'scope':{'origin':[1.50,1.283,-.10], 'size':[1.45,.75,.55], 'front_z':0.0},
 'deck':{'origin':[0,1.018,.65], 'size':[4.30,.22,.32], 'front_z':0.0}}
ports=[]
def add(id,device,x,y,label=None,color='black'):
    assert id not in {p['id'] for p in ports}
    ports.append({'id':id,'device':device,'xyz':[round(x,4),round(y,4),0.0],
                  'normal':[0,0,1], 'face_z':0.0,'color':color,'label':label or id})

for i in range(3):
    x=(i-1)*.45
    add(f'CH{i+1}+','psu',x-.09,-.24,f'CH{i+1} +','red')
    add(f'CH{i+1}-','psu',x+.09,-.24,f'CH{i+1} −','black')
for id,x,color in [('VΩ',-.31,'red'),('COM',0,'black'),('A',.31,'red')]:
    add(id,'meter',x,-.105,id,color)
add('GEN','generator',-.27,-.105,'OUT','red')
add('REF','generator',.27,-.105,'REF','black')
for id,x,color in [('S1',-.43,'yellow'),('S2',0,'cyan'),('GND',.43,'black')]:
    add(id,'scope',x,-.27,id,color)
bank=['IS+','IS-','IS2+','IS2-','IS3+','IS3-','IS4+','IS4-',
      'R1a','R1b','R2a','R2b','Ca','Cb','Da','Db','B1','B2','B3','B4']
for n,id in enumerate(bank):
    add(id,'deck',-1.98+(n%10)*.44,.055 if n<10 else -.055,
        id,'red' if id.endswith(('+','a')) else 'black')

data={'schema':1,'units':'metres','front':'+Z','devices':devices,'ports':ports,
      'movable_breadboard_ports':'X1..X64; omitted from this fixed fixture'}
(OUT/'ports.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(f'{len(ports)} stable fixed ports across {len(devices)} devices')
if __name__=='__main__':pass
