extends SceneTree
const Stream=preload("res://scripts/campus/ai/openai_text_stream.gd")
const Usage=preload("res://scripts/campus/ai/openai_usage.gd")
const Pricing=preload("res://scripts/campus/ai/model_pricing.gd")
const Client=preload("res://scripts/campus/ai/host_openai_client.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value: bool,message: String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)
func stream(path: String="/v1/responses") -> RefCounted:
	var item:=Stream.new()
	item._sse=true;item._headers_read=true;item._status=200;item._path=path;item._limit=262144;item._started=Time.get_ticks_msec()
	return item
func event(item: RefCounted,data: Dictionary,crlf:=false)->void:
	var wire:=("data: "+JSON.stringify(data)+( "\r\n\r\n" if crlf else "\n\n")).to_utf8_buffer()
	for byte in wire:item.consume(PackedByteArray([byte]))
func run()->void:
	var s:=stream()
	event(s,{"type":"response.output_text.delta","delta":"Café — ","sequence_number":1},true)
	event(s,{"type":"response.output_text.delta","delta":"Café — ","sequence_number":1})
	event(s,{"type":"response.output_text.delta","delta":"こんにちは","sequence_number":2})
	check(s._text=="Café — こんにちは","Fragmented multibyte text and duplicate event sequence remain exact")
	check(s.timing.has("first_text_ms") and not s.done,"First text is measured without accepting a partial reply")
	var final:={"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":s._text}]}],"usage":{"input_tokens":12000,"output_tokens":20,"input_tokens_details":{"cached_tokens":4000,"cache_write_tokens":7000,"cache_write_tokens_details":{"ttl_30m_tokens":3000,"ttl_12h_tokens":4000}}}}
	event(s,{"type":"response.completed","response":final,"sequence_number":3})
	var returned: Dictionary=JSON.parse_string(s.result.body.get_string_from_utf8())
	check(s.done and s.result.ok and returned.output[0].content[0].text=="Café — こんにちは" and int(returned.usage.input_tokens)==12000,"Completion preserves full provider response and usage")
	var usage:=Usage.usage_from(final)
	check(usage.get("write_30m")==3000 and usage.get("write_12h")==4000 and usage.get("cache_write")==7000,"Documented nested cache writes are recorded")
	check(Pricing.token_cost({"input":1.,"output":1.,"cached":.1,"write_30m":1.25,"write_12h":2.5},usage)==15170000,"Cache writes are billed once at their retention rate")
	check(Pricing.token_cost({"input":1.,"output":1.},{"input":10,"output":1,"cache_write":5})==-1,"Unknown cache write split cannot fabricate a price")
	var cut:=stream();event(cut,{"type":"response.output_text.delta","delta":"Unfinished"});cut.finish()
	check(not cut.result.ok and cut.result.code=="stream_incomplete" and not cut.result.retryable,"Truncated accepted stream never becomes a reply or an automatic retry")
	var cap:=stream();cap._limit=5;cap.consume("123456".to_utf8_buffer())
	check(cap.done and cap.result.code=="response_size","Transport memory budget is enforced")
	var chat:=stream("/v1/chat/completions")
	event(chat,{"choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}],"model":"fixture"})
	event(chat,{"choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":5,"completion_tokens":1}})
	chat.consume("data: [DONE]\n\n".to_utf8_buffer())
	var result: Dictionary=JSON.parse_string(chat.result.body.get_string_from_utf8())
	check(chat.done and result.choices[0].message.content=="Hello" and result.usage.prompt_tokens==5,"Chat streaming retains final usage and text")
	var cancel:=stream();cancel.cancel()
	check(cancel.result.canceled and not cancel.result.retryable,"Cancellation cannot cause a generation retry")
	var client:=Client.new();root.add_child(client)
	var unknown:=client._record_request("gpt-5.4-mini","text",{"usage":null},false,12,{"request_id":"missing-usage"},{})
	check(unknown.usage.is_empty() and client.request_journal[-1].usage_source=="unreported","Malformed or absent usage stays unknown without crashing accounting")
	client.queue_free()
	print("TEXT_STREAM ","PASS" if failures==0 else "FAIL"," checks=",checks)
	quit(0 if failures==0 else 1)
