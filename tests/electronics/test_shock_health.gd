extends SceneTree
const Shock=preload("res://scripts/campus/health/shock_model.gd")
func _initialize():call_deferred("run")
func run():
 assert(Shock.apply_exposure(100,5,1).health==100)
 assert(Shock.apply_exposure(100,12,1).health<100)
 assert(Shock.apply_exposure(100,12,1,true).health==100)
 assert(Shock.apply_exposure(100,30,1,true).health<100)
 var near_low: float=Shock.apply_exposure(100,29.9,1).health
 var near_high: float=Shock.apply_exposure(100,30.0,1).health
 assert(near_low<100 and near_high<near_low and near_low-near_high<.1)
 assert(Shock.apply_exposure(100,30,2).health<near_high)
 assert(Shock.apply_exposure(100,60,1).health<100)
 assert(not Shock.apply_exposure(100,60,1).arrested)
 assert(Shock.apply_exposure(100,120,1).arrested)
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 var health=game.health;var lab=game.session.lab
 lab.powered=true;lab.recalculate()
 lab.cables.append({"id":999,"a":"P_A","b":"","owner":1,"creator":1,"color":0})
 assert(absf(health._voltage_at(1)-120)<.01)
 health._process(.2)
 assert(health.people[1].arrested and health.locked(1))
 assert(health.guard_position(1,Vector3(4,0,4))==health.people[1].position)
 game.session.request({"op":"return","station":0})
 assert(lab.cables[-1].owner==1)
 lab.powered=false;lab.recalculate();health._process(.2)
 assert(not health.people[1].arrested)
 lab.powered=true;lab.recalculate()
 health.people[1].health=1.0
 health._process(.2)
 assert(health.people[1].dead and health.locked(1))
 assert(lab.cables[-1].owner==0)
 assert(health.people[1].remaining==20.0)
 for i in 105:health._process(.2)
 assert(not health.people[1].dead and health.people[1].health==100)
 assert(game.player.global_position.distance_to(Vector3(13,.05,-18))<.01)
 var dc=game.dc_lab
 dc.carried_leads[1]=0;dc.pending_endpoints[1]={"station":0,"port":"CH1+"}
 dc.benches[0].result={"v":{"CH1+":48.0,"GND":0.0}}
 assert(absf(health._voltage_at(1)-48)<.01)
 dc.pending_endpoints[1]={"station":0,"port":"X1"}
 dc.benches[0].result={"v":{"X1":24.0,"GND":0.0}}
 assert(absf(health._voltage_at(1)-24)<.01)
 print("PASS shock thresholds, arrest, death, respawn and AC/DC/board lead voltage")
 quit()
