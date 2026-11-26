#nullable enable
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Godot;

public partial class CampusNativeClient : RefCounted
{
    private const int MaxInput = 8 * 1024 * 1024;
    private const int MaxFrame = 3 * 1024 * 1024;
    private static int active;
    private readonly object sync = new();
    private Process? child;
    private BinaryWriter? commands;
    private byte[] frame = Array.Empty<byte>();
    private string status = "";
    private bool stopped;
    private Godot.Collections.Dictionary outputs = new();
    private bool running;

    private static string BrokerPath()
    {
        var packaged = Path.Combine(Path.GetDirectoryName(OS.GetExecutablePath())!, "LabVoltCampusBroker.exe");
        return File.Exists(packaged) ? packaged : ProjectSettings.GlobalizePath("res://.godot/LabVoltCampusBroker.exe");
    }

    public bool Available() =>
        System.OperatingSystem.IsWindows() && System.Environment.Is64BitProcess && File.Exists(BrokerPath());

    public bool Start(byte[] data, string storageKey, bool setup)
        => StartMode(data, storageKey, setup ? (byte)1 : (byte)0);

    public bool StartBundle(byte[] data, string storageKey)
        => StartMode(data, storageKey, 2);

    private bool StartMode(byte[] data, string storageKey, byte mode)
    {
        if (!IsStorageKey(storageKey) || (mode == 1 && storageKey.Length != 0) || !Available() || data.Length < 64 ||
            data.Length > (mode == 2 ? CampusWindowsBundle.WireLimit : MaxInput) ||
            Interlocked.CompareExchange(ref active, 1, 0) != 0) return false;
        var trusted = BrokerPath();
        lock (sync)
        {
            running = true;
            stopped = false;
            status = "Starting isolated Windows app.";
            frame = Array.Empty<byte>();
            outputs = new Godot.Collections.Dictionary();
        }
        _ = Task.Run(() => Run(trusted, data, storageKey, mode));
        return true;
    }

    private void Run(string trusted, byte[] data, string storageKey, byte mode)
    {
        Process? process = null;
        try
        {
            process = Process.Start(new ProcessStartInfo(trusted)
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
            }) ?? throw new IOException();
            using var reader = new BinaryReader(process.StandardOutput.BaseStream);
            lock (sync)
            {
                child = process;
                if (stopped) return;
            }
            var writer = new BinaryWriter(process.StandardInput.BaseStream);
            writer.Write(0x4C564E31);
            writer.Write(data.Length);
            writer.Write(mode);
            writer.Write((byte)storageKey.Length);
            writer.Write(Encoding.ASCII.GetBytes(storageKey));
            writer.Write(data);
            writer.Flush();
            lock (sync)
            {
                if (stopped) return;
                commands = writer;
            }
            int outputsBytes = 0;
            int outputsCount = 0;
            while (true)
            {
                byte kind = reader.ReadByte();
                int size = reader.ReadInt32();
                if (kind < 1 || kind > 4 || size < 1 || size > (kind == 2 ? MaxFrame : kind == 4 ? MaxInput + 26 : 1024)) break;
                if (kind == 4 && (mode != 1 || outputsCount >= 8 || outputsBytes + size > MaxInput + 208)) break;
                var bytes = reader.ReadBytes(size);
                if (bytes.Length != size) break;
                lock (sync)
                {
                    if (kind == 2) frame = bytes;
                    else if (kind == 4)
                    {
                        int nameLength = bytes[0];
                        if (nameLength < 5 || nameLength > 24 || bytes.Length <= nameLength + 64) break;
                        var name = Encoding.ASCII.GetString(bytes, 1, nameLength);
                        var payload = bytes[(1 + nameLength)..];
                        if (outputs.ContainsKey(name)) continue;
                        outputs[name] = payload;
                        outputsCount++;
                        outputsBytes += size;
                    }
                    else status = Encoding.UTF8.GetString(bytes);
                }
                if (kind == 3) break;
            }
        }
        catch (Exception)
        {
            lock (sync) if (!stopped) status = "The isolated Windows runtime disconnected.";
        }
        finally
        {
            if (process != null)
            {
                try { if (!process.WaitForExit(1200)) process.Kill(); }
                catch (Exception) {}
                process.Dispose();
            }
            lock (sync)
            {
                commands = null;
                child = null;
                running = false;
            }
            Interlocked.Exchange(ref active, 0);
        }
    }

    private static bool IsStorageKey(string key)
    {
        if (key.Length != 0 && key.Length != 64) return false;
        foreach (char c in key)
            if (!(c is >= '0' and <= '9' or >= 'a' and <= 'f')) return false;
        return true;
    }

    public void Forget(string key)
    {
        if (!IsStorageKey(key) || key.Length == 0 || !System.OperatingSystem.IsWindows()) return;
        _ = Task.Run(async () =>
        {
            for (int i = 0; i < 30 && Volatile.Read(ref active) != 0; i++)
                await Task.Delay(100);
            if (Interlocked.CompareExchange(ref active, 2, 0) != 0) return;
            try
            {
                var root = Path.Combine(System.Environment.GetFolderPath(System.Environment.SpecialFolder.LocalApplicationData),
                    "LabVolt-Campus-Data");
                if (!Directory.Exists(root) || (File.GetAttributes(root) & FileAttributes.ReparsePoint) != 0) return;
                var work = Path.Combine(root, key);
                if (Directory.Exists(work)) DeleteTree(work);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) {}
            finally { Interlocked.Exchange(ref active, 0); }
        });
    }

    private static void DeleteTree(string entry)
    {
        var flags = File.GetAttributes(entry);
        if ((flags & FileAttributes.Directory) == 0) { File.Delete(entry); return; }
        if ((flags & FileAttributes.ReparsePoint) == 0)
            foreach (var child in Directory.EnumerateFileSystemEntries(entry)) DeleteTree(child);
        Directory.Delete(entry);
    }

    public Godot.Collections.Dictionary TakeOutputs()
    {
        lock (sync)
        {
            var result = outputs;
            outputs = new Godot.Collections.Dictionary();
            return result;
        }
    }

    public string Status() { lock (sync) return status; }
    public bool Running() { lock (sync) return running; }
    public byte[] TakeFrame()
    {
        lock (sync)
        {
            var bytes = frame;
            frame = Array.Empty<byte>();
            return bytes;
        }
    }

    public void Forward(int kind, int a, int b, int c)
    {
        lock (sync)
        {
            if (commands == null || stopped || kind is < 1 or > 4) return;
            try
            {
                commands.Write((byte)kind);
                commands.Write(a);
                commands.Write(b);
                commands.Write(c);
                commands.Flush();
            }
            catch (IOException) {}
        }
    }

    public void Stop()
    {
        lock (sync)
        {
            if (stopped || !running) return;
            stopped = true;
            var process = child;
            if (process == null) return;
            try
            {
                commands?.Write((byte)0);
                commands?.Flush();
            }
            catch (IOException) {}
            _ = Task.Run(() =>
            {
                try { if (!process.WaitForExit(1500)) process.Kill(); }
                catch (Exception) {}
            });
        }
    }

    public override void _Notification(int what)
    {
        if (what == NotificationPredelete) Stop();
    }
}
