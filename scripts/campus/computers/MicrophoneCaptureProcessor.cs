using System;
using System.Collections.Generic;
using Godot;

/// <summary>Streaming resampler for the shared capture device. No file or network access.</summary>
public partial class MicrophoneCaptureProcessor : RefCounted
{
    private double position;
    private float previousInput, previousOutput;
    private float noiseFloor = .0015f;
    public void Reset() { position = 0; previousInput = previousOutput = 0; noiseFloor = .0015f; }

    public Godot.Collections.Dictionary Process(Vector2[] frames, double inputRate, float sensitivity, bool noiseGate)
    {
        var result = new Godot.Collections.Dictionary();
        if (frames.Length == 0 || !double.IsFinite(inputRate) || inputRate < 8000 || inputRate > 192000) return result;
        sensitivity = float.IsFinite(sensitivity) ? Math.Clamp(sensitivity, .5f, 2f) : 1f;
        var samples = new List<short>((int)(frames.Length * 16000d / inputRate) + 2);
        double stride = inputRate / 16000d, energy = 0;
        float peak = 0, last = 0;
        int clipped = 0, crossings = 0;
        while (position < frames.Length)
        {
            int index = Math.Clamp((int)position, 0, frames.Length - 1);
            float fraction = (float)(position - index);
            Vector2 a = frames[index], b = frames[Math.Min(index + 1, frames.Length - 1)];
            float sample = ((a.X + a.Y) * (1 - fraction) + (b.X + b.Y) * fraction) * .5f;
            if (!float.IsFinite(sample)) sample = 0;
            if (Math.Abs(sample) >= .99f) clipped++;
            float filtered = sample - previousInput + .97f * previousOutput;
            previousInput = sample; previousOutput = filtered;
            filtered = Math.Clamp(filtered, -1, 1);
            energy += filtered * filtered; peak = Math.Max(peak, Math.Abs(filtered));
            if (filtered * last < 0) crossings++;
            last = filtered; samples.Add((short)MathF.Round(filtered * 32767)); position += stride;
        }
        position -= frames.Length;
        if (samples.Count == 0) return result;
        float rms = (float)Math.Sqrt(energy / samples.Count);
        float threshold = Math.Max(.004f, noiseFloor * 2.8f) / sensitivity;
        float zcr = (float)crossings / samples.Count;
        bool speech = rms >= threshold && zcr > .003f && zcr < .48f;
        if (!speech && rms < threshold * 1.2f) noiseFloor = Math.Clamp(noiseFloor * .98f + rms * .02f, .0004f, .025f);
        // Local noise gate, not acoustic echo cancellation or a neural VAD.
        float gain = noiseGate && !speech && rms < noiseFloor * 1.4f ? .2f : 1f;
        var pcm = new byte[samples.Count * 2];
        for (int i = 0; i < samples.Count; i++)
        {
            short value = (short)(samples[i] * gain);
            pcm[2 * i] = (byte)value; pcm[2 * i + 1] = (byte)(value >> 8);
        }
        result["pcm"] = pcm; result["rms"] = rms; result["peak"] = peak;
        result["noise_floor"] = noiseFloor; result["threshold"] = threshold;
        result["speech"] = speech; result["clipped_samples"] = clipped;
        result["vad"] = "adaptive_energy_and_zero_crossing";
        return result;
    }
    public Vector2[] ToFrames(byte[] pcm)
    {
        var frames = new Vector2[pcm.Length / 2];
        for (int i = 0; i < frames.Length; i++)
        {
            float sample = (short)(pcm[2 * i] | pcm[2 * i + 1] << 8) / 32768f;
            frames[i] = new Vector2(sample, sample);
        }
        return frames;
    }
}
