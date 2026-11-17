extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 game.front.in_game=true
 var health=game.health
 health.people[1].health=64.0
 health.people[1].shocked=true
 health._apply_local();health._shock_feedback(.05)
 assert(health.health_caption.text=="+")
 assert(health.health_value.text=="64 / 100")
 game.campus_services.facilities.controller.host.public_event.emit("cafeteria",1,{"activity":"consume"})
 assert(health.people[1].health==72.0)
 health.people[1].health=99.0
 game.campus_services.facilities.controller.host.public_event.emit("cafeteria",1,{"activity":"consume"})
 assert(health.people[1].health==100.0)
 health.people[1].dead=true
 game.campus_services.facilities.controller.host.public_event.emit("cafeteria",1,{"activity":"consume"})
 assert(health.people[1].health==100.0)
 health.people[1].dead=true
 health._apply_local()
 game.front.pause_menu()
 assert(game.front.screen.visible and health.death_screen.visible and game.front.layer>health.overlay.layer)
 health.people[1].dead=false
 health._apply_local()
 game.player.enabled=false
 health._process(.01)
 assert(not health.bar.visible and not health.health_caption.visible and not health.health_value.visible)
 game.player.enabled=true
 assert(health.shock_flash.color.a>0 and health.spark_views.has(1))
 assert(health.shock_audio.stream is AudioStreamWAV)
 health.people[1].shocked=false
 health._shock_feedback(.05)
 assert(health.shock_flash.color.a==0 and not health.spark_views.has(1))
 print("PASS health label and shock feedback")
 quit()
