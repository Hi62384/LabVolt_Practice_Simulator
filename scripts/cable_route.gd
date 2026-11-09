extends RefCounted
## Deterministic visual clearance around fixed furniture. No physics bodies,
## electrical nets, player collision or remote node/path queries are created.
const CLEARANCE=.022
static func blocked(a:Vector3,b:Vector3,box:AABB)->bool:
 return box.grow(-.00001).intersects_segment(a,b)!=null
static func route(input:Array[Vector3],obstacles:Array[AABB])->Array[Vector3]:
 if input.size()<2 or obstacles.is_empty():return input.duplicate()
 var boxes:Array[AABB]=[]
 for source in obstacles:
  var box=source.grow(CLEARANCE)
  # A held connector inside furniture has no valid fixed-endpoint route.
  if not box.has_point(input[0]) and not box.has_point(input[-1]):boxes.append(box)
 var points:Array[Vector3]=[input[0]]
 for i in range(1,input.size()-1):
  var interior=false
  for box in boxes:
   if box.has_point(input[i]):interior=true;break
  if not interior:points.append(input[i])
 points.append(input[-1])
 for pass_index in 3:
  var changed=false
  for box in boxes:
   var i=0
   while i<points.size()-1 and points.size()<128:
    if blocked(points[i],points[i+1],box):
     var path=detour(points[i],points[i+1],box,boxes)
     if path.size()>2:
      for j in range(1,path.size()-1):points.insert(i+j,path[j])
      i+=path.size()-1;changed=true;continue
    i+=1
  if not changed:break
 return points
static func detour(a:Vector3,b:Vector3,box:AABB,boxes:Array[AABB])->Array[Vector3]:
 var nodes:Array[Vector3]=[a,b]
 for x in 2:
  for y in 2:
   for z in 2:
    var point=box.position+box.size*Vector3(x,y,z)
    if point.y>=.035:nodes.append(point)
 var distance:Array[float]=[];var previous:Array[int]=[];var visited:Array[bool]=[]
 for i in nodes.size():distance.append(INF);previous.append(-1);visited.append(false)
 distance[0]=0.
 for step in nodes.size():
  var nearest=-1
  for i in nodes.size():
   if not visited[i] and (nearest<0 or distance[i]<distance[nearest]):nearest=i
  if nearest<0 or not is_finite(distance[nearest]):break
  if nearest==1:break
  visited[nearest]=true
  for j in nodes.size():
   if visited[j] or j==nearest:continue
   var clear=true
   for other in boxes:
    if blocked(nodes[nearest],nodes[j],other):clear=false;break
   if not clear:continue
   var cost=distance[nearest]+nodes[nearest].distance_to(nodes[j])
   if cost<distance[j]:distance[j]=cost;previous[j]=nearest
 if previous[1]<0:return [a,b]
 var result:Array[Vector3]=[];var index=1
 while index>=0:result.push_front(nodes[index]);index=previous[index]
 return result
