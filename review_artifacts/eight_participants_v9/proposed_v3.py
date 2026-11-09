"""V3 additive type guards; v1/v2 remain preserved."""
import proposed_v2 as v2

def once(base,before,after,course,receipt,paper_binding,request):
    v2.v1.need(type(receipt.get('sequence')) is int, 'ack sequence must be an integer')
    paper=base.official(after)
    v2.v1.need(len(paper)==1 and type(paper[0].get('id')) is int,'observed paper ID must be integer')
    for row in (receipt,paper_binding,request):
        v2.v1.need(type(row.get('paper_id')) is int,'bound paper ID must be integer')
    v2.once(base,before,after,course,receipt,paper_binding,request)

def privacy(base,s,coverage):
    v2.v1.need(type(s.get('peer')) is int and type(coverage.get('peer')) is int,'peer IDs must be integers')
    for p in s['papers']:
        v2.v1.need(type(p.get('id')) is int and type(p.get('owner')) is int,'paper IDs must be integers')
    for category in ('owned_unmarked','foreign'):
        for row in coverage.get(category,[]):
            v2.v1.need(type(row.get('id')) is int,'coverage ID must be integer')
    v2.privacy(base,s,coverage)

def saved(base,s,binding):
    papers=base.official(s)
    v2.v1.need(len(papers)==1 and type(papers[0].get('id')) is int
               and type(binding.get('paper_id')) is int,'saved paper IDs must be integers')
    v2.saved(base,s,binding)

practice=v2.practice
rejoin=v2.rejoin
