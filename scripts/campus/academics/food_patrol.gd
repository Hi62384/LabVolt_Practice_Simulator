extends RefCounted
## Host-only patrol decisions along the food-area aisle, never into classrooms.
const START:=Vector3(18.8,0,33.0)
const MIN_Z:=18.0
const MAX_Z:=48.0
const SPEED:=1.05
var position:=START
var direction:=1.0
var pause:=2.0

func advance(delta: float,blocked: bool) -> bool:
 if pause>0.0:
  pause=maxf(0.0,pause-delta)
  return false
 if blocked:
  direction=-direction;pause=2.0
  return false
 var next:=position.z+direction*SPEED*maxf(0.0,delta)
 position.z=clampf(next,MIN_Z,MAX_Z)
 if next<=MIN_Z or next>=MAX_Z:
  direction=-direction;pause=3.0
 return true
