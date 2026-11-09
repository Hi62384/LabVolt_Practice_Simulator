extends SceneTree
const Board=preload("res://scripts/breadboard_model.gd")
func _initialize():
 var board=Board.empty();board.rows=10;board.ports=["P1","N1","P10","N10"];board.wires=[["P1","A1"],["N10","F10"]]
 board.parts=[{"id":"r","type":"r1000","a":"A1","b":"F1","pins":["A1","F1"]}]
 var expected=[["board/P0","board/L1"],["board/N1","board/R10"],["B1","board/P0"],["B2","board/N0"],["B3","board/P1"],["B4","board/N1"]]
 assert(Board.wires_only(board)==expected)
 board.standalone=true;expected.append_array([["X1","board/L1"],["X2","board/R1"]]);assert(Board.wires_only(board)==expected)
 board.wires.reverse();expected[0]=["board/N1","board/R10"];expected[1]=["board/P0","board/L1"];assert(Board.wires_only(board)==expected)
 var pcb=load("res://tests/remaining/pcb/pcb_tests.gd").fixture()
 var standalone=Board.standalone("ic:pcb",{"ic:pcb":pcb});assert(not standalone.is_empty())
 assert(Board.wires_only(standalone,"pcb/")==Board.expand(standalone,"pcb/").wires)
 standalone.definitions["ic:pcb"].pcb_design.routes.remove_at(1)
 assert(Board.wires_only(standalone,"pcb/")==Board.expand(standalone,"pcb/").wires)
 print("PASS ordered wire mapping, fresh wiring edits, standalone headers and routed PCB fallback")
 quit()
