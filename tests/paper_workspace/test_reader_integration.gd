extends SceneTree
const Reader=preload("res://scripts/paper_ui.gd")
const PaperViewport=preload("res://scripts/ui/paper_workspace/workspace/viewport.gd")
class SchoolStub:
	extends Node
	var papers := {}
	var calls: Array=[]
	func page_count(paper: Dictionary) -> int:
		return 4 if not bool(paper.get("guide",false)) else maxi(1,paper.project.get("guide_pages",[]).size())
	func request(action: Dictionary) -> void:calls.append(action.duplicate(true))
class ReaderFixture:
	extends "res://scripts/paper_ui.gd"
	var rebuilds := 0
	var remembered := 0
	func _build_reader() -> void:rebuilds+=1
	func remember_view() -> void:remembered+=1
var failures: Array[String]=[]
func check(value: bool,label: String) -> void:
	if not value:failures.append(label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var owner := Node.new();root.add_child(owner)
	var school := SchoolStub.new();owner.add_child(school)
	var reader := ReaderFixture.new();owner.add_child(reader);reader.school=school
	var single := {"owner":1,"page":0,"guide":true,"project":{"guide_pages":[{"title":"Only page","text":"Synthetic"}]}}
	var multi := {"owner":1,"page":0,"guide":false,"project":{"questions":[{"prompt":"Synthetic"}]}}
	school.papers={1:single,2:multi};reader.document_id=1;reader.reading=true
	check(reader._page_count(single)==1 and reader._page_count(multi)==4,"guide count follows content; assignment has four actual page sections")
	reader.turn_page(1);check(reader.page_index==0 and reader.rebuilds==0,"single page navigation stays put")
	reader.document_id=2;reader.pending={"0":"42"};reader.turn_page(1)
	check(reader.page_index==1 and reader.rebuilds==1,"next button changes actual multipage index")
	check(school.calls.any(func(action):return action.get("op")=="answer" and action.get("value")=="42"),"pending answer flushes before page rebuild")
	check(school.calls.any(func(action):return action.get("op")=="page" and action.get("page")==1),"owner page request carries selected page")
	reader.turn_page(-1);check(reader.page_index==0,"previous button returns to first page")
	reader.turn_page(-1);check(reader.page_index==0 and reader.rebuilds==2,"boundary button does not rebuild")
	var workspace := PaperViewport.new();workspace.size=Vector2(500,400);owner.add_child(workspace)
	var paper := Control.new();paper.custom_minimum_size=Vector2(780,1100);paper.size=Vector2(780,1100)
	workspace.mount(paper)
	reader.workspace_view=workspace
	reader._set_zoom(99.0,Vector2(250,200));check(is_equal_approx(workspace.target_zoom,PaperViewport.MAX_ZOOM),"wheel zoom clamps upper bound")
	reader._set_zoom(0.01,Vector2(250,200));check(is_equal_approx(workspace.target_zoom,PaperViewport.MIN_ZOOM),"wheel zoom clamps lower bound")
	workspace.restore(1.0,Vector2.ZERO)
	workspace.offset=Vector2(99999,99999);reader._clamp_pan()
	check(Rect2(workspace.offset,paper.size).intersects(Rect2(Vector2.ZERO,workspace.size)),"pan keeps the page reachable")
	owner.queue_free()
	print("PAPER_READER_INTEGRATION_RESULT failures=%d"%failures.size())
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
