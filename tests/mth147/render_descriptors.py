"""File-based mathematical diagram QA; no game render or source PDF images."""
import json
import math
import sys
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

samples=json.loads(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
output=Path(sys.argv[2]);output.parent.mkdir(parents=True,exist_ok=True)
plt.rcParams.update({'font.family':'DejaVu Sans','font.size':12,'axes.spines.top':False,'axes.spines.right':False})
fig,axes=plt.subplots(1,2,figsize=(15,6),layout='constrained')
fig.set_facecolor('#f3f6fa');fig.suptitle('MTH147 · Original generated mathematics',fontsize=21,fontweight='bold',color='#17314c')
p=next(x for x in samples if x['generator_id']=='w8.ssa');solutions=p['answer']['solutions']
ax=axes[0];colors=['#147d89','#ab5a17']
for i,item in enumerate(solutions):
    a,b,c=item['a'],item['b'],item['c'];x=(b*b+c*c-a*a)/(2*c);y=math.sqrt(max(0,b*b-x*x))
    vertices=[(0,0),(c,0),(x,y)];xx=[v[0] for v in vertices]+[0];yy=[v[1] for v in vertices]+[0]
    ax.plot(xx,yy,marker='o',linewidth=2.2,color=colors[i],label=f'Valid triangle {i+1}')
    for point,label in zip(vertices,'ABC'):ax.annotate(label,point,xytext=(4,7),textcoords='offset points',color=colors[i],fontweight='bold')
ax.set_title('SSA: both valid geometries',fontsize=15,pad=18)
proof=p['parameters']['proof'];ax.text(.02,.98,f"Given A = {proof['A']:g}°, a = {proof['a']:.4g}, b = {proof['b']:g}\na is opposite A; drawings use actual coordinates",transform=ax.transAxes,va='top',fontsize=11,bbox={'facecolor':'white','edgecolor':'none','alpha':.85})
ax.axis('equal');ax.grid(alpha=.18);ax.set_xlabel('Horizontal distance (length units)');ax.set_ylabel('Vertical distance (length units)');ax.legend(loc='lower right',frameon=False)
p=next(x for x in samples if x['generator_id']=='w9.graph');d=p['diagram'];f=d['function'];ax=axes[1]
xx=np.linspace(*d['domain'],401);yy=f['offset']+f['amplitude']*getattr(np,f['kind'])(2*np.pi*(xx-f['phase'])/f['period'])
ax.plot(xx,yy,color='#147d89',linewidth=2.5);ax.axhline(f['offset'],color='#8495a5',linestyle='--',linewidth=1,label='Midline')
for point in d['points']:
    ax.scatter(point['x'],point['y'],color='#ab5a17',zorder=4,s=42)
    ax.annotate(point['role'],(point['x'],point['y']),xytext=(0,10 if point['role']!='peak' else -18),textcoords='offset points',ha='center',fontsize=10)
ax.set_title('One complete generated cycle',fontsize=15,pad=18);ax.set_xlabel(d['x_label']);ax.set_ylabel(d['y_label']);ax.grid(alpha=.2);ax.set_ylim(d['range']);ax.ticklabel_format(axis='x',style='sci',scilimits=(-3,4),useMathText=True)
ax.text(.03,.97,f"|A| = {abs(f['amplitude']):g}, T = {f['period']:g} s, f = {1/f['period']:g} Hz\nPhase = {f['phase']:g} s, offset = {f['offset']:g}",transform=ax.transAxes,va='top',fontsize=11,bbox={'facecolor':'white','edgecolor':'none','alpha':.85})
fig.savefig(output,dpi=150,facecolor=fig.get_facecolor());print('DIAGRAM_PREVIEW',output,'triangle solutions',len(solutions),'wave critical points',len(d['points']))
