"""Offline timeline correlation, not automatic root-cause attribution.
Usage: python summarize_hitch_trace.py TRACE.json --output SUMMARY.json
"""
import argparse,json,math
from pathlib import Path

def summarize(data):
    rows=data.get('frames',[])
    phases={}
    for row in rows:
        if row['interval_usec']>0:
            phases.setdefault(row['phase'],[]).append(row['interval_usec']/1000)
    statistics={}
    for phase,values in phases.items():
        values.sort()
        count=len(values);tail=max(1,math.ceil(count*.01))
        statistics[phase]={'samples':count,'average_callback_rate_per_second':1000*count/sum(values),
            'one_percent_low_fps':1000/(sum(values[-tail:])/tail),
            'p99_ms':values[int((count-1)*.99)],'peak_ms':values[-1],
            'retained_interval_seconds':sum(values)/1000}
    windows=[]
    # Hitches retained separately may outlive old frame-ring neighbours.
    for hitch in sorted(data.get('hitches',[]),key=lambda r:r['interval_usec'],reverse=True)[:16]:
        begin=hitch.get('interval_begin_usec',hitch['previous_late_usec']);end=hitch['late_usec']
        neighbours=[r for r in rows if abs(r['sequence']-hitch['sequence'])<=2]
        spans=[s for s in data.get('spans',[]) if s['begin_usec']<=end and s['end_usec']>=begin]
        events=[e for e in data.get('events',[]) if begin<=e['at_usec']<=end]
        windows.append({'hitch':hitch,'neighbour_frames':neighbours,
            'overlapping_wall_spans':spans,'events_in_interval':events,
            'interpretation':'Timestamp overlap locates observed activity only. Wall spans include possible descheduling; render signal gaps are not GPU execution timestamps. No cause assigned.'})
    return {'context':data.get('context',{}),'phase_statistics':statistics,
        'recorded_windows':data.get('windows',[]),'largest_retained_hitches':windows,
        'overwritten':data.get('overwritten',{}),'open_spans':data.get('open_spans',{}),
        'limits':['Phase-start interval is explicitly tagged and retained, including any hitch; callback rates are not presentation FPS.',
            'Latest engine counters have their own sampling timestamps and may update on another cadence.',
            'Only retained records can be correlated. Inspect overwrite counts before claiming complete coverage.',
            'Unmarked subsystem or CPU/render/OS/GPU attribution cannot be inferred automatically.']}

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('trace',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    data=json.loads(args.trace.read_text(encoding='utf-8-sig'))
    result=summarize(data)
    args.output.write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps({'phases':list(result['phase_statistics']),
        'hitches_summarized':len(result['largest_retained_hitches']),
        'cause_assigned':False}))
