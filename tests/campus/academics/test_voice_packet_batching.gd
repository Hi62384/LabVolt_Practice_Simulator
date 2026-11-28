extends SceneTree
const Voice=preload("res://scripts/campus/voice/voice_chat.gd")
func _initialize() -> void:
 var voice:=Voice.new();voice.set_process(false)
 var accepted:=0
 # A healthy 50 Hz microphone can arrive as four packets in one 80 ms frame.
 # The previous inter-arrival gate retained only 25 of these 100 packets.
 for batch in 25:
  var now:=batch*80
  for packet in 4:
   if voice._packet_allowed(1,now):voice.last_packet[1]=now;accepted+=1
 assert(accepted==100,"Frame batching must not discard ordinary voice packets")
 voice.packet_budget.clear();voice.last_packet.clear()
 accepted=0
 for packet in 40:
  if voice._packet_allowed(1,1000):voice.last_packet[1]=1000;accepted+=1
 assert(accepted==12,"Unbounded same-frame floods must still be limited")
 assert(voice._packet_allowed(2,1000),"One speaker's budget must not throttle another")
 assert(voice._packet_allowed(1,1020),"The next ordinary packet is accepted after its time credit")
 voice.free()
 print("VOICE_PACKET_BATCHING PASS (100/100 ordinary batched packets, 12-packet burst bound, independent speakers)")
 quit()
