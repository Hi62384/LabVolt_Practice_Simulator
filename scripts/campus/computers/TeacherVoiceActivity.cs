using System;
using System.Collections.Generic;
using Godot;

/// <summary>Shared-stream speech segmentation. Rollover chunks retain one turn identity.</summary>
public partial class TeacherVoiceActivity : RefCounted
{
    private const int Rate = 16000;
    private const int PreRoll = Rate / 5;
    private const int SegmentSamples = Rate * 30;
    private const int MinimumSpeech = Rate / 8;
    private const int SilenceSamples = Rate * 5 / 4;
    private readonly Queue<short> preRoll = new();
    private readonly List<short> turn = new(SegmentSamples);
    private readonly MicrophoneCaptureProcessor processor = new();
    private int onset, silence, spokenSamples, segment;
    private long turnId;
    private bool speaking;
    public void Reset()
    {
        preRoll.Clear(); turn.Clear(); processor.Reset();
        onset = silence = spokenSamples = segment = 0; speaking = false;
    }
    // Compatibility for fixtures. Playback never increases the input threshold.
    public Godot.Collections.Dictionary Push(Vector2[] frames, double inputRate, float sensitivity, bool otherAudio)
    {
        var data = processor.Process(frames, inputRate, sensitivity, false);
        if (!data.ContainsKey("pcm")) return new Godot.Collections.Dictionary();
        return PushPcm(data["pcm"].AsByteArray(), data["speech"].AsBool());
    }
    public Godot.Collections.Dictionary PushPcm(byte[] pcm, bool voiceDetected)
    {
        var result = new Godot.Collections.Dictionary();
        if (pcm.Length == 0 || pcm.Length % 2 != 0 || pcm.Length > Rate * 2) return result;
        int count = pcm.Length / 2;
        onset = voiceDetected ? onset + count : 0;
        if (!speaking && onset >= Rate * 6 / 100)
        {
            speaking = true; turnId++; segment = spokenSamples = silence = 0;
            turn.AddRange(preRoll); preRoll.Clear(); result["onset"] = true;
        }
        for (int i = 0; i < count; i++)
        {
            short sample = (short)(pcm[i * 2] | pcm[i * 2 + 1] << 8);
            if (speaking) turn.Add(sample);
            else { if (preRoll.Count >= PreRoll) preRoll.Dequeue(); preRoll.Enqueue(sample); }
        }
        if (speaking)
        {
            if (voiceDetected) { spokenSamples += count; silence = 0; }
            else silence += count;
            if (silence >= SilenceSamples) return Finish(result);
            if (turn.Count >= SegmentSamples)
            {
                result["audio"] = Bytes(turn.Count); result["continued"] = true;
                result["segment"] = segment++; result["turn_id"] = turnId; turn.Clear();
            }
        }
        result["speaking"] = speaking; result["turn_id"] = turnId; return result;
    }
    public Godot.Collections.Dictionary Flush()
    {
        return speaking ? Finish(new Godot.Collections.Dictionary()) : new Godot.Collections.Dictionary();
    }
    private Godot.Collections.Dictionary Finish(Godot.Collections.Dictionary result)
    {
        int count = Math.Max(0, turn.Count - Math.Max(0, silence - Rate / 8));
        if (spokenSamples >= MinimumSpeech || segment > 0)
        {
            result["audio"] = Bytes(count); result["continued"] = false;
            result["turn_id"] = turnId; result["segment"] = segment;
            result["speech_seconds"] = (double)spokenSamples / Rate;
        }
        turn.Clear(); preRoll.Clear(); onset = silence = spokenSamples = segment = 0; speaking = false;
        result["speaking"] = false; return result;
    }
    private byte[] Bytes(int count)
    {
        var bytes = new byte[count * 2];
        for (int i = 0; i < count; i++) { bytes[2 * i] = (byte)turn[i]; bytes[2 * i + 1] = (byte)(turn[i] >> 8); }
        return bytes;
    }
}
