using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using LabVolt.Toolchain;

internal sealed class CampusNativeBroker
{
    const int MaxProgram = 8 * 1024 * 1024;
    const int MaxFrame = 3 * 1024 * 1024;
    static readonly BinaryWriter Output = new BinaryWriter(Console.OpenStandardOutput());
    static readonly ConcurrentQueue<Input> Inputs = new ConcurrentQueue<Input>();
    static volatile bool closing;
    static volatile Action stopGuest;
    static int buttons;
    static int queued;
    struct Input { public byte Kind; public int A, B, C; }

    [StructLayout(LayoutKind.Sequential)]
    struct Rect { public int Left, Top, Right, Bottom; }
    delegate bool WindowCallback(IntPtr window, IntPtr state);
    [DllImport("user32.dll")] static extern bool EnumDesktopWindows(IntPtr desktop, WindowCallback callback, IntPtr state);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr window, IntPtr graphics, uint flags);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr window, uint message, IntPtr value, IntPtr position);

    static int Main()
    {
        string job = null;
        try
        {
            var reader = new BinaryReader(Console.OpenStandardInput());
            if (reader.ReadInt32() != 0x4C564E31) return 2;
            int length = reader.ReadInt32();
            if (length < 64 || length > MaxProgram) return 2;
            int mode = reader.ReadByte();
            if (mode > 1) return 2;
            int keyLength = reader.ReadByte();
            if ((keyLength != 0 && keyLength != 64) || (mode == 1 && keyLength != 0)) return 2;
            var key = System.Text.Encoding.ASCII.GetString(reader.ReadBytes(keyLength));
            if (key.Length != keyLength || key.Any(c => !(c >= '0' && c <= '9' || c >= 'a' && c <= 'f'))) return 2;
            var program = reader.ReadBytes(length);
            if (program.Length != length || program[0] != 'M' || program[1] != 'Z') return 2;
            var jobRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "LabVolt-Campus-Processes");
            Directory.CreateDirectory(jobRoot);
            if ((File.GetAttributes(jobRoot) & FileAttributes.ReparsePoint) != 0) return 2;
            job = Path.Combine(jobRoot, Guid.NewGuid().ToString("N"));
            var bin = Path.Combine(job, "program");
            var work = Path.Combine(job, "work");
            if (keyLength != 0)
            {
                var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "LabVolt-Campus-Data");
                EnsureDirectory(root);
                work = Path.Combine(root, key);
            }
            Directory.CreateDirectory(bin);
            EnsureDirectory(work);
            WindowsSandbox.CheckTree(work);
            var image = Path.Combine(bin, "CampusApplication.exe");
            File.WriteAllBytes(image, program);
            var stop = new Thread(delegate() { Receive(reader); }) { IsBackground = true };
            stop.Start();
            var clock = Stopwatch.StartNew();
            using (var box = new WindowsSandbox(true, true))
            {
                stopGuest = box.Stop;
                box.GrantDirectory(bin, false);
                box.GrantDirectory(work, true);
                Send(1, "Starting on an isolated Windows desktop.");
                long nextFrame = 0;
                int exit = box.RunDesktop(image, work, Path.Combine(job, "guest.log"), 9 * 60 * 1000, (pid, desktop) =>
                {
                    if (closing) { box.Stop(); return; }
                    if (clock.ElapsedMilliseconds < nextFrame) return;
                    nextFrame = clock.ElapsedMilliseconds + 100;
                    var window = FindWindow(desktop, pid);
                    if (window == IntPtr.Zero)
                    {
                        if (clock.ElapsedMilliseconds > 20000)
                            throw new InvalidOperationException("This application did not open a capturable window.");
                        return;
                    }
                    ForwardInput(window, pid);
                    Capture(window, pid);
                });
                int count = mode == 1 && exit == 0 && !closing ? CollectExecutables(work) : 0;
                Send(3, count > 0 ? "Setup finished. Import its executable outputs below."
                    : "Windows app closed (" + unchecked((uint)exit).ToString("X8") + ").");
            }
            return 0;
        }
        catch (Exception)
        {
            try { Send(3, "Windows could not run this app in the isolated runtime."); } catch (IOException) {}
            return 1;
        }
        finally
        {
            if (job != null)
            {
                try { WindowsSandbox.CleanupJob(job); Directory.Delete(job, false); } catch (IOException) {} catch (UnauthorizedAccessException) {}
            }
        }
    }

    static int CollectExecutables(string work)
    {
        WindowsSandbox.CheckTree(work);
        int total = 0;
        int count = 0;
        foreach (var file in Directory.EnumerateFiles(work, "*", SearchOption.AllDirectories).OrderBy(n => n, StringComparer.Ordinal))
        {
            if (count >= 8 || total >= MaxProgram) break;
            if (!String.Equals(Path.GetExtension(file), ".exe", StringComparison.OrdinalIgnoreCase)) continue;
            var name = Path.GetFileNameWithoutExtension(file);
            name = new string(name.Where(c => c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' ||
                c >= '0' && c <= '9' || c == ' ' || c == '-' || c == '_').Take(20).ToArray()).Trim();
            if (name.Length == 0) continue;
            byte[] program;
            try { program = WindowsSandbox.ReadBytes(file, MaxProgram - total); }
            catch (Exception) { continue; }
            if (program.Length < 64 || program[0] != 'M' || program[1] != 'Z') continue;
            // A fixed, validated output name and bounded bytes are the only data crossing the boundary.
            using (var record = new MemoryStream())
            using (var writer = new BinaryWriter(record))
            {
                var label = System.Text.Encoding.ASCII.GetBytes(name + ".exe");
                writer.Write((byte)label.Length);
                writer.Write(label);
                writer.Write(program);
                Send(4, record.ToArray());
            }
            total += program.Length;
            count++;
        }
        return count;
    }

    static void EnsureDirectory(string path)
    {
        Directory.CreateDirectory(path);
        if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
            throw new IOException("Reparse point in isolated app storage.");
    }

    static void Send(byte kind, string value) { Send(kind, System.Text.Encoding.UTF8.GetBytes(value)); }
    static void Send(byte kind, byte[] bytes)
    {
        Output.Write(kind);
        Output.Write(bytes.Length);
        Output.Write(bytes);
        Output.Flush();
    }

    static void Receive(BinaryReader reader)
    {
        try
        {
            while (!closing)
            {
                byte kind = reader.ReadByte();
                if (kind == 0) break;
                if (kind > 4) break;
                var input = new Input { Kind = kind, A = reader.ReadInt32(), B = reader.ReadInt32(), C = reader.ReadInt32() };
                if (Interlocked.Increment(ref queued) <= 60) Inputs.Enqueue(input);
                else Interlocked.Decrement(ref queued);
            }
        }
        catch (IOException) {}
        finally { closing = true; var stop = stopGuest; if (stop != null) stop(); }
    }

    static IntPtr FindWindow(IntPtr desktop, uint pid)
    {
        var result = IntPtr.Zero;
        long largest = 0;
        EnumDesktopWindows(desktop, delegate(IntPtr window, IntPtr _)
        {
            uint owner;
            GetWindowThreadProcessId(window, out owner);
            Rect area;
            if (owner != pid || !IsWindowVisible(window) || !GetClientRect(window, out area)) return true;
            long size = (long)area.Right * area.Bottom;
            if (size > largest && area.Right >= 32 && area.Bottom >= 24)
            {
                result = window;
                largest = size;
            }
            return true;
        }, IntPtr.Zero);
        return result;
    }

    static bool Owned(IntPtr window, uint pid)
    {
        uint owner;
        GetWindowThreadProcessId(window, out owner);
        return owner == pid;
    }

    static void Capture(IntPtr window, uint pid)
    {
        Rect area;
        if (!Owned(window, pid) || !GetClientRect(window, out area)) return;
        if (area.Right < 32 || area.Bottom < 24 || area.Right > 1280 || area.Bottom > 900) return;
        using (var bitmap = new Bitmap(area.Right, area.Bottom, PixelFormat.Format32bppRgb))
        using (var graphic = Graphics.FromImage(bitmap))
        {
            var context = graphic.GetHdc();
            bool drawn;
            try { drawn = PrintWindow(window, context, 3); }
            finally { graphic.ReleaseHdc(context); }
            if (!drawn) return;
            using (var data = new MemoryStream())
            {
                bitmap.Save(data, ImageFormat.Png);
                if (data.Length <= MaxFrame) Send(2, data.ToArray());
            }
        }
    }

    static void ForwardInput(IntPtr window, uint pid)
    {
        Rect area;
        if (!GetClientRect(window, out area)) return;
        Input input;
        while (Inputs.TryDequeue(out input))
        {
            Interlocked.Decrement(ref queued);
            if (!Owned(window, pid)) return;
            if (input.Kind == 1)
            {
                if (input.A < 0 || input.B < 0 || input.A > 65535 || input.B > 65535) continue;
                int x = input.A * Math.Min(area.Right - 1, 32767) / 65535;
                int y = input.B * Math.Min(area.Bottom - 1, 32767) / 65535;
                uint msg;
                switch (input.C)
                {
                    case 0: msg = 0x200; break;
                    case 1: msg = 0x201; break;
                    case 2: msg = 0x202; break;
                    case 3: msg = 0x204; break;
                    case 4: msg = 0x205; break;
                    default: continue;
                }
                if (input.C == 1) buttons |= 1;
                if (input.C == 2) buttons &= ~1;
                if (input.C == 3) buttons |= 2;
                if (input.C == 4) buttons &= ~2;
                PostMessage(window, msg, (IntPtr)buttons, (IntPtr)((y << 16) | x));
            }
            else if ((input.Kind == 2 || input.Kind == 3) && input.A >= 8 && input.A <= 135)
                PostMessage(window, input.Kind == 2 ? 0x100U : 0x101U, (IntPtr)input.A,
                    input.Kind == 2 ? (IntPtr)1 : (IntPtr)unchecked((int)0xC0000001));
            else if (input.Kind == 4 && input.A >= 32 && input.A <= 65535 && !char.IsSurrogate((char)input.A))
                PostMessage(window, 0x102, (IntPtr)input.A, (IntPtr)1);
        }
    }
}
