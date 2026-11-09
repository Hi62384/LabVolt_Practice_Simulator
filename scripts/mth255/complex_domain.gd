extends RefCounted
## Course-specific complex domain. Shared parser owns all expression input.
static func add(a: Vector2, b: Vector2) -> Vector2:
	return a+b
static func multiply(a: Vector2, b: Vector2) -> Vector2:
	return Vector2(a.x*b.x-a.y*b.y,a.x*b.y+a.y*b.x)
static func divide(a: Vector2, b: Vector2) -> Vector2:
	if b.length_squared()<1e-20:return Vector2(NAN,NAN)
	return multiply(a,Vector2(b.x,-b.y))/b.length_squared()
static func power(z: Vector2,n: int) -> Vector2:
	if n<0:return divide(Vector2(1,0),power(z,-n))
	var out=Vector2(1,0)
	for _i in range(n):out=multiply(out,z)
	return out
static func polar(r: float,theta: float) -> Vector2:
	return Vector2(r*cos(theta),r*sin(theta))
static func roots(z: Vector2,n: int) -> Array:
	var out=[]
	if n<1 or n>12:return out
	if z.length_squared()==0:return [Vector2.ZERO]
	for k in range(n):out.append(polar(pow(z.length(),1.0/n),(atan2(z.y,z.x)+TAU*k)/n))
	return out
static func encode(z: Vector2) -> Dictionary:
	return {"real":z.x,"imag":z.y}
static func decode(z: Dictionary) -> Vector2:
	return Vector2(float(z.get("real",NAN)),float(z.get("imag",NAN)))
static func valid(z: Vector2) -> bool:
	return is_finite(z.x) and is_finite(z.y)
static func near(a: Vector2,b: Vector2,tolerance: float=0.000001) -> bool:
	return valid(a) and valid(b) and a.distance_to(b)<=tolerance*maxf(1.0,b.length())
static func verify_roots(z: Vector2,values: Array,n: int) -> bool:
	if values.size()!=(1 if z.length_squared()==0 else n):return false
	for i in range(values.size()):
		if not near(power(values[i],n),z,0.00001):return false
		for j in range(i):
			if near(values[i],values[j]):return false
	return true
