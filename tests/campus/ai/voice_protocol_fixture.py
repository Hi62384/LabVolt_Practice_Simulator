"""Loopback-only HTTP/WebSocket protocol fixture. No real OpenAI requests."""
import argparse
import asyncio
import base64
import json
import math
import re
import struct
from aiohttp import web

PCM = b"".join(struct.pack("<h", round(5000 * math.sin(i * .07))) for i in range(4800))
ENCODED = base64.b64encode(PCM).decode()
USAGE = {"input_tokens":100,"output_tokens":40,"input_token_details":{"text_tokens":100,"audio_tokens":0,"cached_tokens":0},"output_token_details":{"text_tokens":10,"audio_tokens":30}}
COUNTS = {"create":0,"active":0,"peak":0,"transcriptions":0,"renders":0}

async def transcription_ws(request):
    ws=web.WebSocketResponse()
    await ws.prepare(request)
    configured=False
    audio=bytearray()
    async for message in ws:
        if message.type!=web.WSMsgType.TEXT:continue
        event=json.loads(message.data)
        kind=event["type"]
        if kind=="session.update":
            session=event["session"]
            assert session["type"]=="transcription"
            config=session["audio"]["input"]
            assert config["format"]=={"type":"audio/pcm","rate":24000}
            assert config["transcription"]["model"] in ["gpt-live-transcribe","gpt-realtime-whisper"]
            assert config["turn_detection"] is None
            configured=True
            await ws.send_json({"type":"session.updated","session":session})
        elif kind=="input_audio_buffer.append":
            assert configured
            audio.extend(base64.b64decode(event["audio"]))
        elif kind=="input_audio_buffer.commit":
            assert len(audio)==14400
            COUNTS["transcriptions"]+=1
            await ws.send_json({"type":"conversation.item.input_audio_transcription.delta","event_id":"early","item_id":"fixture","delta":"What is"})
            await ws.send_json({"type":"input_audio_buffer.committed","item_id":"fixture"})
            await ws.send_json({"type":"conversation.item.input_audio_transcription.completed","item_id":"wrong","transcript":"Wrong"})
            await ws.send_json({"type":"conversation.item.input_audio_transcription.completed","item_id":"fixture","transcript":"What is voltage?"})
        else:
            raise AssertionError(f"Unexpected transcription event: {kind}")
    return ws

async def voice_ws(request):
    assert request.headers.get("Authorization", "").startswith("Bearer sk-fixture-")
    if request.query.get("intent")=="transcription":
        return await transcription_ws(request)
    live = request.path.endswith("/live/sessions")
    assert not live or not request.query
    ws=web.WebSocketResponse()
    await ws.prepare(request)
    COUNTS["active"]+=1
    COUNTS["peak"]=max(COUNTS["peak"],COUNTS["active"])
    text=""
    started=False
    emitted=False
    delegated=False
    dialogue_blocks={}
    if not live:
        assert request.query["model"]=="gpt-realtime-2.1-mini"
        await ws.send_json({"type":"session.created","session":{"id":"rt_fixture"}})
    try:
        async for message in ws:
            if message.type!=web.WSMsgType.TEXT:continue
            event=json.loads(message.data)
            kind=event["type"]
            if kind=="session.start":
                assert live and not started
                session=event["session"]
                assert session["model"]=="gpt-live-1.1"
                assert session["delegation"]["type"]=="client"
                assert session["audio"]["format"]["type"]=="audio/pcm"
                assert session["audio"]["format"]["rate"] in [16000,24000]
                assert session.get("store") is False
                for item in session.get("input",[]):
                    for part in item.get("content",[]):
                        found=re.search(r"<say>(.*?)</say>",part.get("text",""),re.S)
                        if found:text=found.group(1)
                started=True
                await ws.send_json({"type":"session.started","session":{"id":"live_fixture"}})
                await ws.send_json({"type":"session.usage.updated","usage":{"seconds":2}})
                if not text:
                    # This independent utterance must never reach playback.
                    await ws.send_json({"type":"session.output_audio.delta","delta":ENCODED})
                    await ws.send_json({"type":"session.output_transcript.delta","delta":"An invented answer.","start_ms":0,"end_ms":100})
            elif kind=="session.update":
                assert not live
                session=event["session"]
                assert session["type"]=="realtime"
                assert session["audio"]["input"]["turn_detection"] is None
                assert session["output_modalities"]==["audio"]
                assert session["tools"]==[]
                await ws.send_json({"type":"session.updated","session":{"id":"rt_fixture"}})
            elif kind=="conversation.item.create":
                text=event["item"]["content"][0]["text"]
            elif kind=="response.create":
                assert not live and text
                COUNTS["renders"]+=1
                if "Rate limit" in text:
                    await ws.send_json({"type":"error","error":{"code":"rate_limit_exceeded","message":"private fixture secret"}})
                    continue
                if "Cancel" in text:await asyncio.sleep(.5)
                else:await asyncio.sleep(.08)
                if ws.closed:continue
                spoken="Incorrect answer." if "Mismatch" in text else text
                encoded=base64.b64encode(bytes(len(PCM))).decode() if "Silent audio" in text else ENCODED
                await ws.send_json({"type":"response.output_audio.delta","delta":encoded})
                if "Missing transcript" not in text:
                    await ws.send_json({"type":"response.output_audio_transcript.done","transcript":spoken})
                await ws.send_json({"type":"response.done","response":{"status":"completed","usage":USAGE}})
            elif kind=="session.input_audio.append":
                assert live and started
                pcm=base64.b64decode(event["audio"])
                assert len(pcm)%2==0
                if text and not emitted:
                    emitted=True
                    COUNTS["renders"]+=1
                    await ws.send_json({"type":"session.output_audio.delta","delta":ENCODED})
                    await ws.send_json({"type":"session.output_transcript.delta","delta":text,"start_ms":0,"end_ms":200})
                elif not text and not delegated:
                    delegated=True
                    for index,part in enumerate(["What", " is ", "voltage?"]):
                        await ws.send_json({"type":"session.input_transcript.delta","event_id":f"input_{index}","delta":part,"start_ms":index*100,"end_ms":(index+1)*100})
                    delegation={"type":"session.delegation.created","event_id":"delegation_event","offset_ms":300,"delegation":{"id":"delegation_fixture","type":"delegation","target":"client"}}
                    await ws.send_json(delegation)
                    await ws.send_json(delegation)
            elif kind=="session.instructions.append":
                assert "delegation_id" in event
                assert len(event["content"].encode())<=480
                found=re.search(r"<say>(.*?)</say>",event["content"],re.S)
                staged=re.search(r"Perform the exact dialogue supplied in validated dialogue ([0-9a-f]+) parts",event["content"])
                if staged:
                    text="".join(dialogue_blocks[staged.group(1)])
                    await ws.send_json({"type":"session.output_audio.delta","delta":ENCODED})
                    await ws.send_json({"type":"session.output_transcript.delta","delta":text,"start_ms":400,"end_ms":600})
                    emitted=True
                if found:
                    text=found.group(1)
                    await ws.send_json({"type":"session.output_audio.delta","delta":ENCODED})
                    await ws.send_json({"type":"session.output_transcript.delta","delta":text,"start_ms":400,"end_ms":600})
                    emitted=True
            elif kind=="session.thinking.append":
                assert len(event["content"].encode())<=480
                block=re.match(r"Validated dialogue ([0-9a-f]+) part (\d+)/(\d+):\n(.*)",event["content"],re.S)
                if block:dialogue_blocks.setdefault(block.group(1),[]).append(block.group(4))
            elif kind=="session.close":
                assert live
                if "Slow finalization" in text:await asyncio.sleep(.3)
                await ws.send_json({"type":"session.usage.updated","usage":{"seconds":4}})
                await ws.send_json({"type":"session.closed","reason":"client_closed","session":{"id":"live_fixture"},"usage":{"seconds":4}})
                # The client releases the transport after observing session.closed.
            elif kind not in ["response.cancel","session.input_audio.mute","session.input_audio.unmute"]:
                raise AssertionError(f"Unsupported event: {kind}")
    except ConnectionResetError:
        pass
    finally:
        COUNTS["active"]-=1
    return ws

async def resource(request):
    if request.path=="/stats":return web.json_response(COUNTS)
    assert request.headers.get("Authorization", "").startswith("Bearer sk-fixture-")
    if request.path=="/v1/audio/voices":
        data=await request.json()
        assert data["type"]=="prompt" and data["model"]=="auto"
        COUNTS["create"]+=1
        return web.json_response({"object":"audio.voice","type":"prompt","id":"voice_fixture","name":data["name"],"prompt":data["prompt"],"created_at":123})
    if request.path=="/v1/audio/transcriptions":
        data=await request.post()
        assert data["model"]=="gpt-transcribe"
        raw=data["file"].file.read()
        assert raw[:4]==b"RIFF" and len(raw)<=5760044
        COUNTS["transcriptions"]+=1
        return web.json_response({"text":"This is a long recognized question. "*30,"languages":[{"code":"en"}]})
    if request.path=="/v1/chat/completions":
        data=await request.json()
        assert data["model"]=="gpt-audio-1.5"
        assert data["modalities"]==["text","audio"]
        assert data["audio"]=={"voice":"ash","format":"wav"}
        spoken=data["messages"][-1]["content"]
        if "Mismatch" in spoken:spoken="Incorrect answer."
        wav=struct.pack("<4sI4s4sIHHIIHH4sI",b"RIFF",36+len(PCM),b"WAVE",b"fmt ",16,1,1,24000,48000,2,16,b"data",len(PCM))+PCM
        return web.json_response({"choices":[{"finish_reason":"stop","message":{"audio":{"data":base64.b64encode(wav).decode(),"transcript":spoken}}}],"usage":USAGE})
    if request.path=="/v1/responses":
        await asyncio.sleep(.2)
        return web.json_response({"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"fixture answer"}]}]})
    return web.json_response({"data":[{"id":x} for x in ["gpt-realtime-2.1-mini","gpt-live-1.1","gpt-transcribe","gpt-5.4-mini"]]})

if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--port",type=int,default=28823)
    args=parser.parse_args()
    app=web.Application(client_max_size=8*1024*1024)
    app.router.add_get("/v1/live/sessions",voice_ws)
    app.router.add_get("/v1/realtime",voice_ws)
    app.router.add_route("*","/{tail:.*}",resource)
    web.run_app(app,host="127.0.0.1",port=args.port,print=None)
