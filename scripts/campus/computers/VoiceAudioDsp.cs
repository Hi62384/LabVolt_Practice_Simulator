using Godot;
using System;
using System.Diagnostics;

/// <summary>CPU-heavy PCM conversion and clip-level speech normalization, outside GDScript.</summary>
public partial class VoiceAudioDsp : RefCounted
{
    private const int MaxBytes = 16_000_000;

    public Godot.Collections.Dictionary NormalizePcm16(byte[] pcm, int rate, bool stereo, string projection)
    {
        var result = new Godot.Collections.Dictionary { ["ok"] = false };
        int channels = stereo ? 2 : 1;
        if (rate < 8000 || rate > 48000 || pcm.Length == 0 || pcm.Length > MaxBytes || pcm.Length % (channels * 2) != 0)
        {
            result["error"] = "Invalid PCM16 format, sample rate or size.";
            return result;
        }
        var watch = Stopwatch.StartNew();
        int blockSamples = Math.Max(1, rate / 100) * channels;
        double totalEnergy = 0, blockEnergy = 0;
        int speechSamples = 0, blockCount = 0;
        float peak = 0;
        for (int at = 0; at < pcm.Length; at += 2)
        {
            float sample = Read(pcm, at) / 32768f;
            peak = Math.Max(peak, Math.Abs(sample));
            blockEnergy += sample * sample;
            blockCount++;
            if (blockCount == blockSamples || at + 2 == pcm.Length)
            {
                // Gate silence/noise below -54 dBFS; this is RMS, not a LUFS claim.
                if (blockEnergy / blockCount >= 0.000004)
                {
                    totalEnergy += blockEnergy;
                    speechSamples += blockCount;
                }
                blockEnergy = 0;
                blockCount = 0;
            }
        }
        double rms = speechSamples > 0 ? Math.Sqrt(totalEnergy / speechSamples) : 0;
        double targetDb = projection switch
        {
            "whisper" => -27,
            "quiet" => -23,
            "lecture" => -18,
            "shout" => -16,
            _ => -20,
        };
        double gain = rms > 0.0001 ? Math.Clamp(Math.Pow(10, targetDb / 20) / rms, 0.25, 4.0) : 1;
        // One gain for the whole utterance preserves expressive internal dynamics.
        // Limit peak to -0.54 dBFS before independent output-bus protection.
        if (peak > 0) gain = Math.Min(gain, 0.94 / peak);
        var data = new byte[pcm.Length];
        for (int at = 0; at < pcm.Length; at += 2)
        {
            int value = Math.Clamp((int)Math.Round(Read(pcm, at) * gain), -32768, 32767);
            data[at] = (byte)value;
            data[at + 1] = (byte)(value >> 8);
        }
        result["ok"] = true;
        result["data"] = data;
        result["rms_db"] = rms > 0 ? 20 * Math.Log10(rms) : -120;
        result["peak_db"] = peak > 0 ? 20 * Math.Log10(peak) : -120;
        result["gain_db"] = 20 * Math.Log10(Math.Max(gain, 0.000001));
        result["target_db"] = targetDb;
        result["elapsed_us"] = watch.Elapsed.TotalMicroseconds;
        return result;
    }

    public Vector2[] Pcm16ToFrames(byte[] pcm, bool stereo = false)
    {
        int stride = stereo ? 4 : 2;
        if (pcm.Length == 0 || pcm.Length > MaxBytes || pcm.Length % stride != 0) return Array.Empty<Vector2>();
        var frames = new Vector2[pcm.Length / stride];
        for (int frame = 0, at = 0; frame < frames.Length; frame++, at += stride)
        {
            float left = Read(pcm, at) / 32768f;
            frames[frame] = new Vector2(left, stereo ? Read(pcm, at + 2) / 32768f : left);
        }
        return frames;
    }

    private static short Read(byte[] pcm, int at) => (short)(pcm[at] | (pcm[at + 1] << 8));
}
