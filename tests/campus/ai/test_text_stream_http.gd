extends SceneTree
const Client=preload("res://scripts/campus/ai/host_openai_client.gd")
var calls: Array=[]
var failures:=0
var checks:=0
var received_at:=-1
var cancelled:={}
var queued:={}
func _initialize()->void:run.call_deferred()
func check(value: bool,message: String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)
func partial(text: String)->void:
	if received_at<0:received_at=Time.get_ticks_msec()
	calls.append(text)
func start_cancel(client: Node)->void:
	cancelled.result=await client._request_text("HTTP_FIXTURE_STREAM",client.model,384,"low",true,{"request_id":"stream-cancel","_text_progress":partial},3.)
	cancelled.done=true
func start_queued(client: Node,valid: Dictionary)->void:
	queued.result=await client._request_text("HTTP_FIXTURE_STREAM",client.model,384,"low",true,{"request_id":"queued-guard","_valid":func():return valid.current},3.)
	queued.done=true
func run()->void:
	create_timer(20.).timeout.connect(func():quit(1))
	var client:=Client.new();root.add_child(client)
	var base:="http://127.0.0.1:"+OS.get_environment("LABVOLT_OPENAI_FIXTURE_PORT")+"/v1"
	check(client.set_local_test_endpoint(base) and client.set_session_key("sk-test-12345678901234567890"),"Real HTTP fixture configured")
	client.configure("gpt-5.4-mini",384,"low",true)
	var start:=Time.get_ticks_msec()
	var result: Dictionary=await client._request_text("HTTP_FIXTURE_STREAM",client.model,384,"low",true,{"_text_progress":partial,"subsystem":"npc_conversation","request_purpose":"character_turn","origin":"player"},3.)
	var finish:=Time.get_ticks_msec()
	check(result.get("ok",false) and result.get("text")=="Café — complete response.","Incremental HTTP response preserves exact Unicode text")
	check(received_at>=start and finish-received_at>=100 and calls.size()==2,"Real transport delivers first text before delayed completion")
	check(int(result.timing.first_text_ms)<int(result.timing.total_ms) and result.timing.has("connection_ms"),"Connection and first-text timings come from actual events")
	check(result.measurement.usage=={"input":101,"output":37,"cached":64,"reasoning":8},"Terminal provider usage is counted exactly once")
	check(client.request_journal.size()==1 and client.request_journal[0].purpose=="character_turn" and client.request_journal[0].usage_source=="provider","Central journal identifies subsystem and provider reporting")
	check(not JSON.stringify(client.request_diagnostics()).contains("sk-test") and not JSON.stringify(client.request_diagnostics()).contains("Café"),"Diagnostics contain no credentials or conversation text")
	calls.clear();received_at=-1
	start_cancel(client)
	while received_at<0 and not cancelled.get("done",false):await process_frame
	client.cancel_speech_request("stream-cancel")
	while not cancelled.get("done",false):await process_frame
	check(cancelled.result.get("canceled",false) and not cancelled.result.get("ok",true) and not cancelled.result.has("text"),"Cancel after first text discards partial output without another generation")
	check(client.session_requests==2 and client.active_requests.is_empty() and not client.busy,"Cancellation releases the exact request and records one attempt")
	check(cancelled.result.measurement.usage.is_empty(),"Canceled stream without terminal usage keeps token counts unknown")
	client._lane_active.text=Client.LANE_LIMITS.text
	var valid:={"current":true}
	start_queued(client,valid)
	await process_frame
	check(not queued.get("done",false) and client._lane_waiting.text.size()==1,"A saturated text lane holds the pending request")
	valid.current=false
	while not queued.get("done",false):await process_frame
	check(queued.result.get("canceled",false) and client.session_requests==2 and client._lane_waiting.text.is_empty(),"Closing a queued conversation cancels before network dispatch without a billable retry")
	client._lane_active.text=0;client.busy=false
	client.configure("gpt-6.2-astra",384,"low",true)
	var cached: Dictionary=await client._request_text("HTTP_FIXTURE_CACHE",client.model,384,"low",true,{},3.,"Reusable rules. ".repeat(300))
	check(cached.get("ok",false),"Supported modern model accepts explicit reusable developer prefix")
	print("TEXT_STREAM_HTTP ","PASS" if failures==0 else "FAIL"," checks=",checks," first_text_ms=",result.timing.first_text_ms," total_ms=",result.timing.total_ms," source=loopback fixture with 150ms authored completion delay; not live provider performance")
	client.queue_free();await process_frame;quit(0 if failures==0 else 1)
