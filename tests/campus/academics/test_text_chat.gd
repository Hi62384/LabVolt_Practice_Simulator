extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 3:await process_frame
 game.front.entered();game.player.enabled=true
 var chat=game.text_chat
 chat._focus()
 assert(chat.typing and game.player.chat_typing and chat.entry.max_length==100)
 chat._submit("hello campus")
 assert(not chat.typing and not game.player.chat_typing)
 assert(chat.log.get_child(chat.log.get_child_count()-1).text.ends_with("hello campus"))
 for i in 5:chat._received(1,"Student","message %d"%i)
 assert(chat.bubbles[1].size()==4)
 assert(chat.bubbles[1][0].node.get_child(0).size==Vector2i(512,144))
 chat.clock+=11;chat._process(.6);assert(chat.panel.modulate.a==0.0)
 chat._received(1,"Student","wake");assert(chat.panel.modulate.a==1.0)
 chat.clock+=16;chat._process(.1);assert(not chat.bubbles.has(1))
 chat._received(1,"Student","before reconnect")
 assert(chat.bubbles.has(1))
 chat._reset_session()
 assert(chat.bubbles.is_empty())
 print("PASS chat focus, send, four bubbles and fade")
 quit()
