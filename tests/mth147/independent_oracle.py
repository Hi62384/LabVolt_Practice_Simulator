"""Independent Fraction/geometry oracle for Godot-generated fixtures; no eval/CAS.

This test-only parser has its own lexer and arithmetic. It never executes source.
Run with the generated JSONL path. Production uses only the bounded GDScript core.
"""
from __future__ import annotations
import itertools
import json
import math
import re
import sys
from collections import Counter
from decimal import Decimal, ROUND_HALF_UP
from fractions import Fraction as F
from pathlib import Path

TOKEN = re.compile(r"\s*(?:(\d+(?:\.\d*)?(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?)|([A-Za-z]+\d*)|([+*/^(),!-]))")

def ordinal(value):
    """JSON normalizes integer metadata to floats; reject fractional corruption."""
    assert isinstance(value,(int,float)) and not isinstance(value,bool)
    assert math.isfinite(value) and value==int(value) and abs(value)<=10**12
    return int(value)

class Parser:
    def __init__(self, source):
        source = str(source)
        if len(source) > 512: raise ValueError("source budget")
        self.tokens = []
        offset = 0
        while offset < len(source):
            match = TOKEN.match(source, offset)
            if not match: raise ValueError("unknown token")
            self.tokens.append(next(x for x in match.groups() if x is not None))
            offset = match.end()
        if len(self.tokens)>256: raise ValueError("token budget")
        self.tokens.append("END");self.i=0;self.nodes=0
    def take(self):
        value=self.tokens[self.i];self.i+=1;return value
    def parse(self):
        tree=self.expr(0,0)
        if self.tokens[self.i]!="END":raise ValueError("trailing token")
        return tree
    def expr(self, minimum, depth):
        self.nodes+=1
        if depth>24 or self.nodes>192:raise ValueError("tree budget")
        token=self.take()
        if token in ("+","-"):left=("neg",self.expr(25,depth+1)) if token=="-" else self.expr(25,depth+1)
        elif token=="(":
            left=self.expr(0,depth+1)
            if self.take()!=")":raise ValueError("parenthesis")
        elif token[0].isdigit() or token[0]==".":left=("num",F(token))
        elif token[0].isalpha():
            if self.tokens[self.i]=="(":
                self.take();args=[self.expr(0,depth+1)]
                while self.tokens[self.i]==",":self.take();args.append(self.expr(0,depth+1))
                if self.take()!=")":raise ValueError("function parenthesis")
                left=(token,*args)
            else:left=("symbol",token)
        else:raise ValueError("operand")
        while True:
            token=self.tokens[self.i]
            if token=="!":self.take();left=("factorial",left);continue
            binding={"+":10,"-":10,"*":20,"/":20,"^":30}.get(token,-1)
            if binding<minimum:break
            self.take();left=({"+":"add","-":"sub","*":"mul","/":"div","^":"pow"}[token],left,self.expr(binding if token=="^" else binding+1,depth+1))
        return left

def parse(text):return Parser(text).parse()

def evaluate(tree, symbols=None):
    symbols=symbols or {};op=tree[0]
    if op=="num":return tree[1]
    if op=="symbol":return math.pi if tree[1]=="pi" else symbols[tree[1]]
    args=[evaluate(x,symbols) for x in tree[1:]];a=args[0]
    if op=="neg":return -a
    if op=="add":return a+args[1]
    if op=="sub":return a-args[1]
    if op=="mul":return a*args[1]
    if op=="div":return a/args[1]
    if op=="pow":
        b=args[1]
        if abs(b)>100:raise ValueError("power budget")
        if isinstance(b,F) and b.denominator==1:return a**int(b)
        if a<0 and isinstance(b,F) and b.denominator%2:return (-1 if b.numerator%2 else 1)*abs(float(a))**float(b)
        return float(a)**float(b)
    if op=="sqrt":return math.sqrt(a)
    if op=="cbrt":return math.copysign(abs(float(a))**(1/3),a)
    if op=="root":return math.copysign(abs(float(args[1]))**(1/float(a)),args[1])
    if op in ("sin","cos","tan"):return getattr(math,op)(math.radians(a))
    if op in ("sec","csc","cot"):
        t=math.radians(a);return {"sec":lambda:1/math.cos(t),"csc":lambda:1/math.sin(t),"cot":lambda:math.cos(t)/math.sin(t)}[op]()
    if op in ("asin","acos","atan"):return math.degrees(getattr(math,op)(a))
    if op=="abs":return abs(a)
    if op=="factorial":return F(math.factorial(int(a)))
    if op=="choose":return F(math.comb(int(a),int(args[1])))
    if op=="ln":return math.log(a)
    if op=="log":return math.log(a,args[1])
    if op=="exp":return math.exp(a)
    if op=="atan2":return math.degrees(math.atan2(a,args[1]))
    raise ValueError("function whitelist: "+op)

def val(source, symbols=None):return evaluate(parse(source),symbols)
def close(a,b,absolute=1e-8,relative=1e-8):return math.isfinite(float(a)) and math.isfinite(float(b)) and abs(float(a)-float(b))<=max(absolute,relative*max(abs(float(a)),abs(float(b))))
def same_set(a,b):
    a=list(a);b=list(b)
    if len(a)!=len(b):return False
    for x in a:
        match=next((i for i,y in enumerate(b) if close(x,y,1e-6)),None)
        if match is None:return False
        b.pop(match)
    return True

def p_add(a,b,sign=1):
    out=a.copy()
    for degree,coefficient in b.items():out[degree]=out.get(degree,F(0))+sign*coefficient
    return {k:v for k,v in out.items() if v} or {0:F(0)}
def p_mul(a,b):
    out={}
    for i,x in a.items():
        for j,y in b.items():
            if i+j>24:raise ValueError("polynomial budget")
            out[i+j]=out.get(i+j,F(0))+x*y
    return {k:v for k,v in out.items() if v} or {0:F(0)}
def rational(tree, variable="x"):
    op=tree[0]
    if op=="num":return {0:tree[1]},{0:F(1)}
    if op=="symbol":
        if tree[1]!=variable:raise ValueError("foreign variable")
        return {1:F(1)},{0:F(1)}
    if op=="neg":
        n,d=rational(tree[1],variable);return {k:-v for k,v in n.items()},d
    a,b=rational(tree[1],variable)
    if op=="pow":
        exponent=val_tree_constant(tree[2]);n=int(exponent)
        if exponent!=n or abs(n)>12:raise ValueError("integer polynomial power")
        if n<0:a,b=b,a;n=-n
        num={0:F(1)};den={0:F(1)}
        for _ in range(n):num=p_mul(num,a);den=p_mul(den,b)
        return num,den
    c,d=rational(tree[2],variable)
    if op in ("add","sub"):return p_add(p_mul(a,d),p_mul(c,b),1 if op=="add" else -1),p_mul(b,d)
    if op=="mul":return p_mul(a,c),p_mul(b,d)
    if op=="div":return p_mul(a,d),p_mul(b,c)
    raise ValueError("nonrational tree")
def val_tree_constant(tree):return evaluate(tree,{})
def roots(poly):
    degree=max(poly)
    if degree==0:return []
    if degree==1:return [-poly.get(0,F(0))/poly[1]]
    if degree!=2:raise ValueError("root solver bounded at quadratic")
    a,b,c=poly[2],poly.get(1,F(0)),poly.get(0,F(0));discriminant=b*b-4*a*c
    if discriminant<0:return []
    if discriminant==0:return [-b/(2*a)]
    n=math.isqrt(discriminant.numerator);d=math.isqrt(discriminant.denominator)
    root=F(n,d) if n*n==discriminant.numerator and d*d==discriminant.denominator else math.sqrt(discriminant)
    return [(-b+root)/(2*a),(-b-root)/(2*a)]
def equation_roots(left,right,variable="x"):
    a,b=rational(parse(left),variable);c,d=rational(parse(right),variable)
    candidates=roots(p_add(p_mul(a,d),p_mul(c,b),-1));out=[]
    for x in candidates:
        try:
            if close(val(left,{variable:x}),val(right,{variable:x})):out.append(x)
        except (ZeroDivisionError,ValueError):pass
    return out
def restrictions(tree):
    out=[]
    if tree[0]=="div":
        n,_=rational(tree[2]);out+=roots(n)
    for child in tree[1:]:
        if isinstance(child,tuple):out+=restrictions(child)
    unique=[]
    for x in out:
        if not any(close(x,y) for y in unique):unique.append(x)
    return unique
def determinant(matrix):
    result=F(0);n=len(matrix)
    for permutation in itertools.permutations(range(n)):
        inversions=sum(permutation[i]>permutation[j] for i in range(n) for j in range(i+1,n))
        term=F((-1)**inversions)
        for i,j in enumerate(permutation):term*=matrix[i][j]
        result+=term
    return result
def system(matrix,rhs):
    rows=[row[:]+[b] for row,b in zip(matrix,rhs)];r=0;n=len(matrix)
    for c in range(n):
        pivot=next((j for j in range(r,n) if rows[j][c]),None)
        if pivot is None:continue
        rows[r],rows[pivot]=rows[pivot],rows[r];divisor=rows[r][c];rows[r]=[x/divisor for x in rows[r]]
        for j in range(n):
            if j!=r:
                factor=rows[j][c];rows[j]=[x-factor*y for x,y in zip(rows[j],rows[r])]
        r+=1
    if any(not any(row[:-1]) and row[-1] for row in rows):return "none",[]
    if r<n:return "infinite",[]
    return "unique",[row[-1] for row in rows]
def tri_ok(d):
    sides=d['sides'];angles=d['angles'];v=d['vertices']
    assert close(sum(angles.values()),180)
    for i,side in enumerate('abc'):
        j,k=(i+1)%3,(i+2)%3
        assert close(math.hypot(v[j]['x']-v[k]['x'],v[j]['y']-v[k]['y']),sides[side])
        x,y,z=sides[side],sides['abc'[j]],sides['abc'[k]]
        assert x+y>z and x+z>y and y+z>x
        assert close(math.cos(math.radians(angles[side.upper()])),(y*y+z*z-x*x)/(2*y*z))
def wave(f,x):return f['offset']+f['amplitude']*getattr(math,f['kind'])(2*math.pi*(x-f['phase'])/f['period'])
def factor_leaves(tree):
    if tree[0]=='mul':return factor_leaves(tree[1])+factor_leaves(tree[2])
    if tree[0]=='neg':return factor_leaves(tree[1])
    if tree[0]=='pow':
        n=evaluate(tree[2])
        if n==int(n) and 0<int(n)<=12:return factor_leaves(tree[1])*int(n)
    return [tree]

def verify(p):
    proof=p['parameters']['proof'];kind=proof['kind'];answer=p['answer'];original=proof.get('original',p['parameters']['expression'])
    if kind in ('identity','factor','radical_identity','rearrange'):
        lhs,rhs=(original,str(answer)) if kind!='rearrange' else (proof['left'],proof['right'])
        a,b=parse(lhs),parse(rhs);count=0
        for t in (F(7,13),F(17,11),F(-9,8),F(29,7),F(1,31)):
            bindings={name:t+F(i,7) for i,name in enumerate('xyz tvabcdpir'.replace(' ',''))}
            try:
                if kind=='rearrange':bindings[proof['target']]=val(answer,bindings)
                x,y=evaluate(a,bindings),evaluate(b,bindings)
            except (ZeroDivisionError,ValueError):continue
            assert x==y if isinstance(x,F) and isinstance(y,F) else close(x,y,1e-7)
            count+=1
        assert count>=2
        if kind=='factor':
            n1,d1=rational(a);n2,d2=rational(b)
            assert not any(p_add(p_mul(n1,d2),p_mul(n2,d1),-1).values())
            for leaf in factor_leaves(b):
                polynomial,_=rational(leaf);degree=max(polynomial);assert degree<=2
                if degree==2:assert not any(isinstance(root,F) for root in roots(polynomial))
    elif kind=='numeric':
        absolute=1e-14 if p['generator_id'] in ('w8.ratio','w8.reciprocal') else 1e-90
        assert close(val(original),val(answer),absolute,1e-9)
    elif kind=='factoring_method':
        polynomial,_=rational(parse(original));degree=max(polynomial);nonzero=sum(bool(x) for x in polynomial.values())
        expected='perfect_square' if nonzero==3 else 'difference_squares' if degree%2==0 else 'sum_cubes' if polynomial[0]>0 else 'difference_cubes'
        assert answer==expected
    elif kind=='binomial_terms':
        for x in (F(-2),F(1,3),F(5,7)):
            bindings={'x':x,'y':x+F(2,5)};a=val(proof['first'],bindings);b=val(proof['second'],bindings);n=ordinal(proof['n'])
            expected=sum(F(math.comb(n,k))*a**(n-k)*b**k for k in range(ordinal(proof['count'])))
            assert val(answer,bindings)==expected
    elif kind=='rounding':
        value=Decimal(str(proof['original']));place=value.adjusted()-ordinal(proof['digits'])+1
        expected=value.quantize(Decimal(1).scaleb(place),rounding=ROUND_HALF_UP)
        assert Decimal(str(answer))==expected
    elif kind=='equation':assert same_set(equation_roots(proof['left'],proof['right'],proof['variable']),[val(x) for x in answer])
    elif kind=='division':
        for x in (F(-3,2),F(0),F(5,7),F(4)):
            bindings={proof['variable']:x}
            assert val(proof['dividend'],bindings)==val(proof['divisor'],bindings)*val(answer['quotient'],bindings)+val(answer['remainder'],bindings)
        remainder,_=rational(parse(answer['remainder']),proof['variable']);divisor,_=rational(parse(proof['divisor']),proof['variable'])
        assert max(remainder)<max(divisor) or not any(remainder.values())
    elif kind in ('system','determinant','model'):
        matrix=[[F(ordinal(x[0]),ordinal(x[1])) for x in row] for row in proof['matrix']]
        if kind=='determinant':assert determinant(matrix)==val(answer)
        else:
            classification,values=system(matrix,[F(ordinal(x[0]),ordinal(x[1])) for x in proof['rhs']])
            if 'classification' in answer:assert classification==answer['classification']
            else:
                assert classification=='unique'
                for name,value in answer.items():
                    if name in 'xyz':assert values['xyz'.index(name)]==val(value)
                    elif name.startswith('balance'):
                        i=int(name[-1])-1
                        for x,y in [(F(1,3),F(7,5)),(F(-2),F(3))]:assert val(value,{'x':x,'y':y})==matrix[i][0]*x+matrix[i][1]*y-F(ordinal(proof['rhs'][i][0]),ordinal(proof['rhs'][i][1]))
    elif kind=='symbolic_system':
        for a in (F(-3),F(0),F(5,7),F(12)):
            bindings={'a':a,**{key:val(value) for key,value in answer.items()}}
            assert all(val(x,bindings)==val(y,bindings) for x,y in zip(proof['left'],proof['right']))
    elif kind in ('rational','restrictions'):
        expected=restrictions(parse(original));supplied=answer['excluded'] if kind=='rational' else answer
        assert same_set(expected,[val(x) for x in supplied])
        if kind=='rational':
            for x in (F(-11,7),F(17,3),F(29,11)):
                if any(close(x,y) for y in expected):continue
                assert val(original,{'x':x})==val(answer['expression'],{'x':x})
    elif kind=='nested_radical':assert close(val(original),val(answer)) and val(answer)>=0
    elif kind=='variable_radical':
        for x in (F(0),F(2,7),F(3),F(8)):assert close(val(original,{'x':x}),val(answer,{'x':x}))
    elif kind=='radical_equation':
        a,b,c,d=[F(int(proof[k])) for k in ('a','b','c','d')]
        candidates=roots({2:c*c,1:2*c*d-a,0:d*d-b});valid=[]
        for x in candidates:
            if a*x+b>=0 and c*x+d>=0 and close(math.sqrt(a*x+b),c*x+d):valid.append(x)
        assert same_set(valid,[val(x) for x in answer])
    elif kind=='trig_equation':
        fn=proof['function'];target=proof['target'];alpha=math.asin(target) if fn=='sin' else math.acos(target) if fn=='cos' else math.atan(target)
        phases=[alpha,math.pi-alpha] if fn=='sin' else [alpha,-alpha] if fn=='cos' else [alpha]
        period=math.pi if fn=='tan' else 2*math.pi;expected=[]
        for phase in phases:
            for k in range(-100,101):
                x=(math.degrees(phase+k*period)-proof['shift'])/proof['scale']
                if proof['lo']-1e-7<=x<=proof['hi']+1e-7 and not any(close(x,y,1e-6) for y in expected):expected.append(x)
        assert same_set(expected,[val(x) for x in answer])
    elif kind=='triangle':
        d=proof['descriptor'];tri_ok(d)
        for field in proof['fields']:assert close(val(answer[field]),d['sides'].get(field,d['angles'].get(field)))
    elif kind=='ssa':
        A,a,b=proof['A'],proof['a'],proof['b'];h=b*math.sin(math.radians(A))
        count=0 if a<h-1e-8 else 1 if close(a,h) or a>=b else 2
        assert len(answer['solutions'])==count
        for item in answer['solutions']:
            assert close(item['A'],A) and close(item['a'],a) and close(item['b'],b)
            assert close(item['A']+item['B']+item['C'],180) and item['C']>0
            assert close(item['a']/math.sin(math.radians(item['A'])),item['c']/math.sin(math.radians(item['C'])))
    elif kind=='wave_zeros':
        f=proof['function'];target=-f['offset']/f['amplitude'];expected=[]
        if abs(target)<=1:
            a=math.asin(target) if f['kind']=='sin' else math.acos(target)
            bases=[a,math.pi-a] if f['kind']=='sin' else [a,-a]
            for base in bases:
                for k in range(-2,3):
                    phase=base+2*k*math.pi
                    if -1e-10<=phase<=2*math.pi+1e-10:
                        x=f['phase']+f['period']*phase/(2*math.pi)
                        if not any(close(x,y,1e-7) for y in expected):expected.append(x)
        assert same_set(expected,[val(x) for x in answer])
        assert all(close(wave(f,val(x)),0) for x in answer)
    elif kind in ('wave','wave_compare'):
        f=proof['function'];assert f['period']>0 and f['amplitude']!=0
        for point in proof.get('points',[]):assert close(point['y'],wave(f,point['x']))
        if p['expected_form']=='table':
            assert len(answer['rows'])==1
            assert all(close(val(value),wave(f,point['x'])) for value,point in zip(answer['rows'][0],proof['points']))
        if p['expected_form']=='structured':
            expected={'amplitude':abs(f['amplitude']),'period':f['period'],'frequency':1/f['period'],'phase':f['phase'],'midline':f['offset'],'maximum':f['offset']+abs(f['amplitude']),'minimum':f['offset']-abs(f['amplitude'])}
            if kind=='wave_compare':
                g=proof['other'];expected={'amplitude_ratio':abs(g['amplitude']/f['amplitude']),'period_ratio':g['period']/f['period'],'frequency_ratio':f['period']/g['period'],'shift_change':g['phase']-f['phase']}
            for field,value in answer.items():
                target=wave(f,proof['points'][int(field[1:])]['x']) if field.startswith('y') else expected[field]
                assert close(val(value),target)
    elif kind=='coterminal':assert int(proof['angle'])%360==val(answer)
    elif kind=='quadrant':
        angle=proof['angle']%360
        expected=('positive' if val(f"{proof['function']}({angle})")>0 else 'negative') if proof['ask_sign'] else str(int(angle//90)+1)
        assert answer==expected
    elif kind=='like_terms':
        option=next(x for x in proof['options'] if x['id']==answer)
        poly,_=rational(parse(option['text']),proof['variable']);assert list(poly)==[proof['power']]
    else:raise ValueError('missing oracle '+kind)
    if p.get('diagram',{}).get('kind')=='triangle':tri_ok(p['diagram'])

def main():
    path=Path(sys.argv[1]);counts=Counter();failures=[];cases=0
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        p=json.loads(line);cases+=1
        try:verify(p);counts[p['generator_id']]+=1
        except Exception as exc:failures.append((p['id'],type(exc).__name__,str(exc)))
    for failure in failures[:30]:print('FAIL',*failure)
    print('INDEPENDENT_ORACLE_CASES',cases,'FAMILIES',len(counts),'FAILURES',len(failures))
    sys.exit(bool(failures))
if __name__=='__main__':main()
