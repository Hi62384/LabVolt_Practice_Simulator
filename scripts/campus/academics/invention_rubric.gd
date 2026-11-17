extends RefCounted
## One explicit, measurable DC invention challenge. Called with a fresh host station.
const MIN_LED_A:=0.005
const MAX_LED_A:=0.020

static func evaluate_led(station: RefCounted) -> Dictionary:
	var checks:={"placed_board":false,"fresh_solver":false,"powered":false,"led_present":false,"led_current_in_range":false,"no_overload":false}
	if station==null:return {"passed":false,"checks":checks,"message":"The DC bench is unavailable."}
	checks.placed_board=not station.board.is_empty() and not station.board_held and not station.board_stowed and station.board_simulating() and not station.linked
	checks.fresh_solver=station.solved_board_epoch==station.board_epoch and station.solved_revision==station.revision and bool(station.result.get("ok",false))
	checks.powered=bool(station.master)
	if not checks.placed_board or not checks.fresh_solver or not checks.powered:return {"passed":false,"checks":checks,"message":"Place and power your own board, then wait for a fresh host solver result."}
	var currents: Dictionary=station.result.get("i",{})
	for part in station.netlist():
		if str(part.get("kind",""))!="LED" or not str(part.get("id","")).begins_with("board/"):continue
		checks.led_present=true
		var current:=float(currents.get(str(part.id),NAN))
		if is_finite(current) and current>=MIN_LED_A and current<=MAX_LED_A:checks.led_current_in_range=true
	checks.no_overload=true
	for rating in station.result.get("resistor_ratings",{}).values():
		if bool(rating.get("overloaded",false)):checks.no_overload=false;break
	var passed:=checks.values().all(func(value):return value)
	var message:="Objective met: a board LED carries 5–20 mA with no overloaded resistor." if passed else ("Add a board LED and bring its current into the 5–20 mA range." if checks.led_present else "Add a board LED to this circuit.")
	if not checks.no_overload:message="A resistor is over its power rating. Reduce its load before this objective can pass."
	return {"passed":passed,"checks":checks,"message":message}
