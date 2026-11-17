using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

sealed class Manifest
{
    public int schema { get; set; }
    public string version { get; set; }
    public GameFile[] files { get; set; }
}

sealed class GameFile
{
    public string name { get; set; }
    public long size { get; set; }
    public string sha256 { get; set; }
    public Block[] blocks { get; set; }
}

sealed class Block
{
    public int size { get; set; }
    public string sha256 { get; set; }
}

sealed class Updater
{
    public const string Repository = "https://github.com/Hi62384/LabVolt_Practice_Simulator";
    const int BlockLimit = 8 * 1024 * 1024;
    static readonly Regex Version = new Regex(@"\A[a-f0-9]{40}-[0-9]+-[0-9]+\z");
    static readonly Regex Hash = new Regex(@"\A[a-f0-9]{64}\z");
    static readonly string[] RequiredFiles = { "LabVolt.exe", "LabVolt.pck" };
    static readonly Regex SafeSegment = new Regex(@"\A[A-Za-z0-9_.! -]+\z");
    readonly string root;
    readonly Uri releases;
    readonly Action<string> status;
    readonly int idleTimeoutMs;
    public Action<int> Progress = delegate { };
    readonly JavaScriptSerializer json = new JavaScriptSerializer { MaxJsonLength = 1024 * 1024 };

    public Updater(string root, Uri releases, Action<string> status, int idleTimeoutMs = 30000)
    {
        this.root = root;
        this.releases = releases;
        this.status = status;
        this.idleTimeoutMs = Math.Max(1, idleTimeoutMs);
    }

    public string Installed()
    {
        string pointer = Path.Combine(root, "current");
        if (!File.Exists(pointer)) return null;
        string version = File.ReadAllText(pointer).Trim();
        if (!Version.IsMatch(version)) return null;
        string folder = Path.Combine(root, version);
        try
        {
            Manifest manifest = Parse(File.ReadAllText(Path.Combine(folder, "manifest.json")));
            return manifest.version == version && ValidFiles(folder, manifest) ? folder : null;
        }
        catch (IOException) { return null; }
        catch (InvalidDataException) { return null; }
        catch (InvalidOperationException) { return null; }
        catch (ArgumentException) { return null; }
    }

    public async Task<string> Update()
    {
        for (int attempt = 0; ; attempt++)
        {
            try { return await UpdateOnce(); }
            catch (Exception error)
            {
                // Temporary HTTP failures and truncated/corrupt transfers can
                // both be retried safely: verified blocks remain in the cache.
                if (!(error is WebException) && !(error is InvalidDataException) && !(error is IOException)) throw;
                if (attempt >= 2) throw;
                status("Update check interrupted. Retrying…");
            }
            await Task.Delay(1000 * (attempt + 1));
        }
    }

    async Task<string> UpdateOnce()
    {
        Directory.CreateDirectory(root);
        using (var client = new ReleaseClient(idleTimeoutMs))
        {
            string document;
            // A fresh URL avoids stale proxy or CDN redirects to an older release.
            Uri manifestUri = new Uri(releases, "latest/download/manifest.json?check=" + Guid.NewGuid().ToString("N"));
            using (Stream stream = await OpenRead(client, manifestUri))
            using (var buffer = new MemoryStream())
            {
                byte[] data = new byte[8192];
                int count;
                while ((count = await Read(stream, data)) > 0)
                {
                    if (buffer.Length + count > json.MaxJsonLength) throw new InvalidDataException("Update manifest is too large.");
                    buffer.Write(data, 0, count);
                }
                document = System.Text.Encoding.UTF8.GetString(buffer.ToArray());
            }
            Manifest manifest = Parse(document);
            long total = manifest.files.Sum(f => f.size), completed = 0;
            Progress(0);
            string folder = Path.Combine(root, manifest.version);
            if (!ValidFiles(folder, manifest))
            {
                string cache = Path.Combine(root, "blocks");
                Directory.CreateDirectory(cache);
                string stage = Path.Combine(root, "staging");
                if (Directory.Exists(stage)) Directory.Delete(stage, true);
                Directory.CreateDirectory(stage);
                foreach (GameFile file in manifest.files)
                {
                    status("Updating " + file.name);
                    string destination = Path.Combine(stage, file.name.Replace('/', Path.DirectorySeparatorChar));
                    Directory.CreateDirectory(Path.GetDirectoryName(destination));
                    using (FileStream output = File.Create(destination))
                    {
                        foreach (Block block in file.blocks)
                        {
                            string local = Path.Combine(cache, block.sha256);
                            if (!ValidFile(local, block.size, block.sha256))
                                await DownloadBlock(client, manifest.version, block, local);
                            using (FileStream input = File.OpenRead(local)) input.CopyTo(output);
                            completed += block.size;
                            Progress((int)(completed * 100 / total));
                        }
                    }
                }
                if (!ValidFiles(stage, manifest)) throw new InvalidDataException("The assembled game failed verification.");
                if (Directory.Exists(folder)) Directory.Delete(folder, true);
                Directory.Move(stage, folder);
            }
            WriteAtomic(Path.Combine(folder, "manifest.json"), document);
            SetCurrent(manifest.version);
            Progress(100);
            return folder;
        }
    }

    async Task DownloadBlock(WebClient client, string version, Block block, string local)
    {
        string temporary = local + ".partial";
        Uri url = new Uri(releases, "download/game-" + version + "/" + block.sha256 + ".gz");
        using (Stream source = await OpenRead(client, url))
        using (var compressed = new GZipStream(source, CompressionMode.Decompress))
        using (FileStream output = File.Create(temporary))
        {
            byte[] buffer = new byte[65536];
            int count;
            while ((count = await Read(compressed, buffer)) > 0)
            {
                if (output.Length + count > block.size) throw new InvalidDataException("A download block exceeded its declared size.");
                output.Write(buffer, 0, count);
            }
        }
        if (!ValidFile(temporary, block.size, block.sha256)) throw new InvalidDataException("A download block failed verification.");
        MoveIntoPlace(temporary, local);
    }

    async Task<Stream> OpenRead(WebClient client, Uri url)
    {
        using (var timeout = new CancellationTokenSource(idleTimeoutMs))
        using (timeout.Token.Register(delegate { try { client.CancelAsync(); } catch (ObjectDisposedException) { } }))
        {
            try
            {
                Stream stream = await client.OpenReadTaskAsync(url);
                if (!timeout.IsCancellationRequested) return stream;
                stream.Dispose();
                throw new WebException("The update server timed out.", null, WebExceptionStatus.Timeout, null);
            }
            catch (Exception error)
            {
                if (timeout.IsCancellationRequested)
                    throw new WebException("The update server timed out.", error, WebExceptionStatus.Timeout, null);
                throw;
            }
        }
    }

    async Task<int> Read(Stream stream, byte[] buffer)
    {
        using (var timeout = new CancellationTokenSource(idleTimeoutMs))
        using (timeout.Token.Register(delegate { try { stream.Dispose(); } catch (Exception) { } }))
        {
            try
            {
                int count = await stream.ReadAsync(buffer, 0, buffer.Length, timeout.Token);
                if (timeout.IsCancellationRequested)
                    throw new WebException("The update download stalled.", null, WebExceptionStatus.Timeout, null);
                return count;
            }
            catch (Exception error)
            {
                if (timeout.IsCancellationRequested)
                    throw new WebException("The update download stalled.", error, WebExceptionStatus.Timeout, null);
                throw;
            }
        }
    }

    Manifest Parse(string document)
    {
        Manifest manifest;
        try { manifest = json.Deserialize<Manifest>(document); }
        catch (ArgumentException error) { throw new InvalidDataException("Invalid game manifest.", error); }
        catch (InvalidOperationException error) { throw new InvalidDataException("Invalid game manifest.", error); }
        if (manifest == null || manifest.schema != 1 || !Version.IsMatch(manifest.version ?? "") ||
            manifest.files == null || manifest.files.Length < 2 || manifest.files.Length > 500 ||
            manifest.files.Any(f => f == null || !SafeName(f.name)) ||
            manifest.files.Select(f => f.name).Distinct(StringComparer.OrdinalIgnoreCase).Count() != manifest.files.Length ||
            RequiredFiles.Any(name => !manifest.files.Any(f => f.name == name)))
            throw new InvalidDataException("Unsupported game manifest.");
        foreach (GameFile file in manifest.files)
        {
            if (file.size <= 0 || file.size > 4L * 1024 * 1024 * 1024 ||
                !Hash.IsMatch(file.sha256 ?? "") || file.blocks == null || file.blocks.Length == 0 ||
                file.blocks.Any(b => b == null || b.size <= 0 || b.size > BlockLimit || !Hash.IsMatch(b.sha256 ?? "")) ||
                file.blocks.Sum(b => (long)b.size) != file.size)
                throw new InvalidDataException("Invalid game file description.");
        }
        return manifest;
    }

    static bool SafeName(string name)
    {
        if (name == "LabVolt.exe" || name == "LabVolt.pck") return true;
        if (String.IsNullOrEmpty(name) || name.Length > 120 || name.Contains("\\") || name.Contains(":")) return false;
        string[] parts = name.Split('/');
        if (parts.Length == 1)
            return new HashSet<string>(StringComparer.OrdinalIgnoreCase) {
                "chrome_100_percent.pak", "chrome_200_percent.pak", "chrome_elf.dll",
                "d3dcompiler_47.dll", "dxcompiler.dll", "gdCefRenderProcess.exe",
                "icudtl.dat", "libcef.dll", "libgdcef.dll", "resources.pak",
                "v8_context_snapshot.bin", "vk_swiftshader_icd.json",
                "vk_swiftshader.dll", "vulkan-1.dll"
            }.Contains(name);
        if (parts[0] != "piper" && parts[0] != "teacher_voices" &&
            parts[0] != "locales" && parts[0] != "data_CollegeSimulator_windows_x86_64") return false;
        return parts.Skip(1).All(part => part != "." && part != ".." && SafeSegment.IsMatch(part));
    }

    static bool ValidFiles(string folder, Manifest manifest)
    {
        return manifest.files.All(file => ValidFile(Path.Combine(folder, file.name), file.size, file.sha256));
    }

    static bool ValidFile(string path, long length, string hash)
    {
        var file = new FileInfo(path);
        if (!file.Exists || file.Length != length) return false;
        using (var sha = SHA256.Create())
        using (FileStream stream = file.OpenRead())
            return String.Equals(BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", ""), hash, StringComparison.OrdinalIgnoreCase);
    }

    void SetCurrent(string version)
    {
        WriteAtomic(Path.Combine(root, "current"), version);
    }

    static void WriteAtomic(string pointer, string value)
    {
        if (File.Exists(pointer) && File.ReadAllText(pointer) == value) return;
        string temporary = pointer + ".partial";
        File.WriteAllText(temporary, value);
        MoveIntoPlace(temporary, pointer);
    }

    [DllImport("kernel32.dll", EntryPoint = "MoveFileExW", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool MoveFileEx(string source, string destination, int flags);

    static void MoveIntoPlace(string temporary, string destination)
    {
        const int ReplaceExisting = 1;
        const int WriteThrough = 8;
        if (!MoveFileEx(temporary, destination, ReplaceExisting | WriteThrough))
            throw new IOException("Could not activate the verified update.", new System.ComponentModel.Win32Exception());
    }

    sealed class ReleaseClient : WebClient
    {
        readonly int timeoutMs;
        public ReleaseClient(int timeoutMs) { this.timeoutMs = timeoutMs; }
        protected override WebRequest GetWebRequest(Uri address)
        {
            var request = (HttpWebRequest)base.GetWebRequest(address);
            request.Timeout = timeoutMs;
            request.ReadWriteTimeout = timeoutMs;
            request.UserAgent = "LabVoltLauncher/1";
            request.CachePolicy = new System.Net.Cache.RequestCachePolicy(System.Net.Cache.RequestCacheLevel.NoCacheNoStore);
            return request;
        }
    }
}

sealed class LauncherButton : Button
{
    public bool Primary;
    bool hovered;
    bool pressed;

    public LauncherButton()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
        Cursor = Cursors.Hand;
    }

    protected override void OnMouseEnter(EventArgs e) { hovered = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hovered = false; pressed = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseDown(MouseEventArgs e) { pressed = true; Invalidate(); base.OnMouseDown(e); }
    protected override void OnMouseUp(MouseEventArgs e) { pressed = false; Invalidate(); base.OnMouseUp(e); }
    protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
    protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
    protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }

    protected override void OnPaint(PaintEventArgs e)
    {
        Color background = Enabled ? BackColor : (Primary ? Color.FromArgb(29, 73, 72) : Color.FromArgb(28, 49, 59));
        if (Enabled && hovered) background = ControlPaint.Light(background, pressed ? 0.03f : 0.13f);
        Color foreground = Enabled ? ForeColor : Color.FromArgb(154, 179, 183);
        e.Graphics.Clear(background);
        using (var border = new Pen(Enabled && Focused ? Color.FromArgb(147, 238, 220) : Color.FromArgb(70, 109, 120)))
            e.Graphics.DrawRectangle(border, 0, 0, Width - 1, Height - 1);
        TextRenderer.DrawText(e.Graphics, Text, Font, ClientRectangle, foreground,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis);
    }
}

sealed class LauncherProgress : Control
{
    int value;
    public int Value { get { return value; } set { this.value = Math.Max(0, Math.Min(100, value)); Invalidate(); } }

    public LauncherProgress()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        int diameter = Math.Max(2, Math.Min(Height - 1, Width - 1));
        var bounds = new Rectangle(0, 0, Width - 1, Height - 1);
        using (var outline = new GraphicsPath())
        {
            outline.AddArc(bounds.Left, bounds.Top, diameter, diameter, 90, 180);
            outline.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 180);
            outline.CloseFigure();
            using (var track = new SolidBrush(Color.FromArgb(38, 65, 76))) e.Graphics.FillPath(track, outline);
            if (value > 0)
            {
                var previous = e.Graphics.Save();
                e.Graphics.SetClip(new Rectangle(0, 0, (int)Math.Ceiling(Width * value / 100.0), Height));
                using (var fill = new SolidBrush(Color.FromArgb(99, 215, 193))) e.Graphics.FillPath(fill, outline);
                e.Graphics.Restore(previous);
            }
        }
    }
}

sealed class Launcher : Form
{
    readonly Label status = new Label();
    readonly Label progressText = new Label();
    readonly LauncherProgress progress = new LauncherProgress();
    readonly LauncherButton play = new LauncherButton { Primary = true };
    readonly LauncherButton check = new LauncherButton();
    readonly Updater updater;
    string game;

    Launcher()
    {
        Text = "College Simulator";
        ClientSize = new Size(940, 650);
        MinimumSize = new Size(956, 689);
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Color.FromArgb(15, 31, 42);
        ForeColor = Color.FromArgb(235, 245, 247);
        Font = new Font("Segoe UI", 10);
        var hero = new Panel { Dock = DockStyle.Top, Height = 300, BackColor = Color.FromArgb(23, 50, 63) };
        var laboratory = new PictureBox { Dock = DockStyle.Fill, SizeMode = PictureBoxSizeMode.Zoom };
        var campus = new PictureBox { Dock = DockStyle.Right, Width = 350, SizeMode = PictureBoxSizeMode.Zoom };
        using (Stream image = typeof(Launcher).Assembly.GetManifestResourceStream("CollegeSimulator.Laboratory.png"))
            if (image != null) using (var original = Image.FromStream(image)) laboratory.Image = new Bitmap(original);
        using (Stream image = typeof(Launcher).Assembly.GetManifestResourceStream("CollegeSimulator.Campus.png"))
            if (image != null) using (var original = Image.FromStream(image)) campus.Image = new Bitmap(original);
        hero.Controls.Add(laboratory);
        hero.Controls.Add(campus);
        var body = new Panel { Dock = DockStyle.Fill, Padding = new Padding(34, 20, 34, 25) };
        var badge = new Label { Text = "CAMPUS  /  SIMULATION", Location = new Point(34, 20), Size = new Size(550, 25),
            ForeColor = Color.FromArgb(113, 213, 201), Font = new Font("Segoe UI", 9, FontStyle.Bold) };
        var title = new Label { Text = "College Simulator", Location = new Point(30, 43), Size = new Size(800, 54),
            Font = new Font("Segoe UI", 25, FontStyle.Bold) };
        var subtitle = new Label { Text = "Your campus. Your lab. Your next discovery.", Location = new Point(34, 100), Size = new Size(800, 26),
            ForeColor = Color.FromArgb(174, 195, 202) };
        status.SetBounds(34, 150, 850, 38);
        status.ForeColor = Color.FromArgb(205, 221, 225);
        progress.SetBounds(34, 195, 780, 12);
        progressText.SetBounds(824, 187, 65, 28);
        progressText.TextAlign = ContentAlignment.MiddleRight;
        progressText.ForeColor = Color.FromArgb(113, 213, 201);
        ConfigureButton(play, "LAUNCH GAME", Color.FromArgb(74, 193, 177), Color.FromArgb(12, 41, 43));
        play.SetBounds(34, 235, 420, 58);
        play.Font = new Font("Segoe UI", 13, FontStyle.Bold);
        play.Enabled = false;
        ConfigureButton(check, "Check for updates", Color.FromArgb(35, 62, 75), Color.White);
        check.SetBounds(466, 235, 220, 58);
        body.Controls.AddRange(new Control[] { badge, title, subtitle, status, progress, progressText, play, check });
        Controls.Add(body);
        Controls.Add(hero);
        updater = new Updater(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "LabVolt Launcher"), new Uri(Updater.Repository + "/releases/"), Report);
        updater.Progress = ReportProgress;
        Shown += async delegate { await RefreshGame(); };
        check.Click += async delegate { await RefreshGame(); };
        play.Click += delegate
        {
            try
            {
                Process.Start(new ProcessStartInfo(Path.Combine(game, "LabVolt.exe")) { WorkingDirectory = game });
                Close();
            }
            catch (Exception error) { Report(error.Message); }
        };
    }

    static void ConfigureButton(Button button, string text, Color background, Color foreground)
    {
        button.Text = text;
        button.BackColor = background;
        button.ForeColor = foreground;
        button.FlatStyle = FlatStyle.Flat;
        button.FlatAppearance.BorderSize = 0;
        button.UseVisualStyleBackColor = false;
        button.Cursor = Cursors.Hand;
    }

    void Report(string message)
    {
        if (IsDisposed || !IsHandleCreated) return;
        if (InvokeRequired) { BeginInvoke(new Action<string>(Report), message); return; }
        status.Text = message;
    }

    void ReportProgress(int value)
    {
        if (IsDisposed || !IsHandleCreated) return;
        if (InvokeRequired) { BeginInvoke(new Action<int>(ReportProgress), value); return; }
        progress.Value = Math.Max(0, Math.Min(100, value));
        progressText.Text = progress.Value + "%";
    }

    async Task RefreshGame()
    {
        play.Enabled = check.Enabled = false;
        ReportProgress(0);
        Report("Checking for updates…");
        string failure = null;
        try
        {
            game = await Task.Run(() => updater.Update());
            Report("You're up to date and ready to play.");
        }
        catch (Exception error) { failure = error.Message; }
        if (failure != null)
        {
            try { game = await Task.Run(() => updater.Installed()); }
            catch (IOException) { game = null; }
            catch (UnauthorizedAccessException) { game = null; }
            Report((game == null ? "Update failed. " : "Update unavailable; the installed game is ready. ") + failure);
        }
        if (IsDisposed) return;
        play.Enabled = game != null;
        check.Enabled = true;
    }

    [STAThread]
    public static void Main()
    {
        ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
        bool first;
        using (var mutex = new Mutex(true, @"Local\LabVoltLauncher-v1", out first))
        {
            if (!first) return;
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new Launcher());
        }
    }
}
