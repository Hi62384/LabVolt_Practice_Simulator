extends SceneTree
var compiler: Node
var deadline := 0
var board := "uno"
func _initialize() -> void:
 compiler=preload("res://scripts/firmware_toolchain/compile_service.gd").new()
 root.call_deferred("add_child",compiler)
 compiler.finished.connect(_finished)
 call_deferred("_start")
func _start() -> void:
 board=OS.get_environment("LABVOLT_TEST_BOARD")
 if board.is_empty():board="uno"
 var source: Dictionary={"main.ino":"void setup(){pinMode(13,OUTPUT);}\nvoid loop(){digitalWrite(13,HIGH);}"}
 var entry: String="main.ino"
 if board=="pico":
  source={"main.cpp":'#include "labvolt_pico.h"\nint main(){lv_gpio_output(25);for(;;){lv_gpio_write(25,1);}}'}
  entry="main.cpp"
 var result: Dictionary=compiler.start(board,source,entry)
 if not result.get("ok",false):
  printerr("FIRMWARE_COMPILE FAIL "+JSON.stringify(result));quit(1);return
 deadline=Time.get_ticks_msec()+720000
func _process(_delta: float) -> bool:
 if deadline>0 and Time.get_ticks_msec()>deadline:
  printerr("FIRMWARE_COMPILE TIMEOUT");quit(1)
 return false
func _finished(result: Dictionary) -> void:
 if not result.get("ok",false) or not result.get("firmware",{}) is Dictionary or str(result.firmware.get("image","")).is_empty():
  printerr("FIRMWARE_COMPILE FAIL "+JSON.stringify(result));quit(1);return
 print("FIRMWARE_COMPILE PASS "+board)
 quit()
