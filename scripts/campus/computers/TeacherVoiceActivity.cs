using System;
using System.Collections.Generic;
using Godot;

/// <summary>Bounded per-player microphone segmentation with pre-roll.</summary>
public partial class TeacherVoiceActivity : RefCounted
{
    private const int Rate = 16000;
    private const int PreRoll = Rate / 5;
    private const int MaxSamples = Rate * 7;
    private const int MinimumSpeech = Rate / 5;
    private const int SilenceSamples = Rate * 17 / 10;
    private readonly Queue<short> preRoll = new();
    private readonly List<short> turn = new(MaxSamples);
    private float floor = .007f;
    private double position;
    private int onset;
    private int silence;
    private int calibrating = Rate / 3;
    private bool speaking;

    public void Reset()
    {
        preRoll.Clear();
        turn.Clear();
        floor = .007f;
        position = 0;
        onset = silence = 0;
        calibrating = Rate / 3;
        speaking = false;
    }

    public Godot.Collections.Dictionary Push(Vector2[] frames, double inputRate, float sensitivity, bool otherAudio)
    {
        var result = new Godot.Collections.Dictionary();
        if (frames.Length == 0 || inputRate < 8000 || inputRate > 192000) return result;
        float energy = 0;
        foreach (var frame in frames)
        {
            float sample = (frame.X + frame.Y) * .5f;
            energy += sample * sample;
        }
        float rms = MathF.Sqrt(energy / frames.Length);
        sensitivity = Math.Clamp(sensitivity, .5f, 2f);
        double stride = inputRate / Rate;
        int estimate = (int)(frames.Length / stride);
        if (calibrating > 0)
        {
            floor = Math.Clamp((floor + rms) * .5f, .002f, .045f);
            calibrating -= estimate;
        }
        float threshold = Math.Max(otherAudio ? .048f : .012f, floor * (otherAudio ? 6f : 3.2f)) / sensitivity;
        bool loud = calibrating <= 0 && rms > threshold;
        if (!speaking && !loud && !otherAudio)
            floor = Math.Clamp(floor * .985f + rms * .015f, .002f, .045f);
        if (loud) onset += estimate;
        else onset = 0;
        if (!speaking && onset >= Rate / 10)
        {
            speaking = true;
            result["onset"] = true;
            turn.AddRange(preRoll);
            preRoll.Clear();
        }

        while (position < frames.Length)
        {
            var frame = frames[(int)position];
            short sample = (short)(Math.Clamp((frame.X + frame.Y) * .5f, -1f, 1f) * 32767f);
            if (speaking)
            {
                if (turn.Count < MaxSamples) turn.Add(sample);
            }
            else
            {
                if (preRoll.Count == PreRoll) preRoll.Dequeue();
                preRoll.Enqueue(sample);
            }
            position += stride;
        }
        position -= frames.Length;

        if (speaking)
        {
            silence = loud ? 0 : silence + estimate;
            if (silence >= SilenceSamples || turn.Count == MaxSamples)
            {
                int count = turn.Count - Math.Max(0, silence - Rate / 8);
                if (count >= MinimumSpeech)
                {
                    byte[] bytes = new byte[Math.Max(count, Rate) * 2];
                    for (int i = 0; i < count; i++)
                    {
                        bytes[i * 2] = (byte)turn[i];
                        bytes[i * 2 + 1] = (byte)(turn[i] >> 8);
                    }
                    result["audio"] = bytes;
                }
                turn.Clear();
                silence = onset = 0;
                speaking = false;
            }
        }
        result["speaking"] = speaking;
        return result;
    }
}
