using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
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
    static readonly string[] FileNames = { "LabVolt.exe", "LabVolt.pck" };
    readonly string root;
    readonly Uri releases;
    readonly Action<string> status;
    readonly JavaScriptSerializer json = new JavaScriptSerializer { MaxJsonLength = 1024 * 1024 };

    public Updater(string root, Uri releases, Action<string> status)
    {
        this.root = root;
        this.releases = releases;
        this.status = status;
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
        catch (InvalidOperationException) { return null; }
        catch (ArgumentException) { return null; }
    }

    public async Task<string> Update()
    {
        Directory.CreateDirectory(root);
        using (var client = new ReleaseClient())
        {
            string document;
            using (Stream stream = await client.OpenReadTaskAsync(new Uri(releases, "latest/download/manifest.json")))
            using (var buffer = new MemoryStream())
            {
                byte[] data = new byte[8192];
                int count;
                while ((count = await stream.ReadAsync(data, 0, data.Length)) > 0)
                {
                    if (buffer.Length + count > json.MaxJsonLength) throw new InvalidDataException("Update manifest is too large.");
                    buffer.Write(data, 0, count);
                }
                document = System.Text.Encoding.UTF8.GetString(buffer.ToArray());
            }
            Manifest manifest = Parse(document);
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
                    using (FileStream output = File.Create(Path.Combine(stage, file.name)))
                    {
                        foreach (Block block in file.blocks)
                        {
                            string local = Path.Combine(cache, block.sha256);
                            if (!ValidFile(local, block.size, block.sha256))
                                await DownloadBlock(client, manifest.version, block, local);
                            using (FileStream input = File.OpenRead(local)) input.CopyTo(output);
                        }
                    }
                }
                if (!ValidFiles(stage, manifest)) throw new InvalidDataException("The assembled game failed verification.");
                if (Directory.Exists(folder)) Directory.Delete(folder, true);
                Directory.Move(stage, folder);
            }
            WriteAtomic(Path.Combine(folder, "manifest.json"), document);
            SetCurrent(manifest.version);
            return folder;
        }
    }

    async Task DownloadBlock(WebClient client, string version, Block block, string local)
    {
        string temporary = local + ".partial";
        Uri url = new Uri(releases, "download/game-" + version + "/" + block.sha256 + ".gz");
        using (Stream source = await client.OpenReadTaskAsync(url))
        using (var compressed = new GZipStream(source, CompressionMode.Decompress))
        using (FileStream output = File.Create(temporary))
        {
            byte[] buffer = new byte[65536];
            int count;
            while ((count = await compressed.ReadAsync(buffer, 0, buffer.Length)) > 0)
            {
                if (output.Length + count > block.size) throw new InvalidDataException("A download block exceeded its declared size.");
                output.Write(buffer, 0, count);
            }
        }
        if (!ValidFile(temporary, block.size, block.sha256)) throw new InvalidDataException("A download block failed verification.");
        MoveIntoPlace(temporary, local);
    }

    Manifest Parse(string document)
    {
        Manifest manifest = json.Deserialize<Manifest>(document);
        if (manifest == null || manifest.schema != 1 || !Version.IsMatch(manifest.version ?? "") ||
            manifest.files == null || manifest.files.Length != FileNames.Length ||
            !manifest.files.Where(f => f != null).Select(f => f.name).OrderBy(n => n, StringComparer.Ordinal).SequenceEqual(FileNames))
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
        protected override WebRequest GetWebRequest(Uri address)
        {
            var request = (HttpWebRequest)base.GetWebRequest(address);
            request.Timeout = 30000;
            request.ReadWriteTimeout = 30000;
            request.UserAgent = "LabVoltLauncher/1";
            request.CachePolicy = new System.Net.Cache.RequestCachePolicy(System.Net.Cache.RequestCacheLevel.NoCacheNoStore);
            return request;
        }
    }
}

sealed class Launcher : Form
{
    readonly Label status = new Label { AutoSize = false, Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter };
    readonly Button play = new Button { Text = "Play", AutoSize = true, Enabled = false };
    readonly Button check = new Button { Text = "Check for updates", AutoSize = true };
    readonly Updater updater;
    string game;

    Launcher()
    {
        Text = "LabVolt Launcher";
        ClientSize = new Size(480, 210);
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        BackColor = Color.FromArgb(18, 37, 48);
        ForeColor = Color.White;
        Font = new Font("Segoe UI", 11);
        var heading = new Label { Text = "LabVolt Cooperative Lab", Dock = DockStyle.Top, Height = 65,
            TextAlign = ContentAlignment.MiddleCenter, Font = new Font("Segoe UI", 18, FontStyle.Bold) };
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 55,
            FlowDirection = FlowDirection.RightToLeft, Padding = new Padding(12, 4, 12, 4) };
        play.ForeColor = check.ForeColor = Color.Black;
        buttons.Controls.Add(play);
        buttons.Controls.Add(check);
        Controls.Add(status);
        Controls.Add(buttons);
        Controls.Add(heading);
        updater = new Updater(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "LabVolt Launcher"), new Uri(Updater.Repository + "/releases/"), Report);
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

    void Report(string message)
    {
        if (IsDisposed || !IsHandleCreated) return;
        if (InvokeRequired) { BeginInvoke(new Action<string>(Report), message); return; }
        status.Text = message;
    }

    async Task RefreshGame()
    {
        play.Enabled = check.Enabled = false;
        Report("Checking GitHub for updates…");
        string failure = null;
        try
        {
            game = await Task.Run(() => updater.Update());
            Report("Game is up to date.");
        }
        catch (Exception error) { failure = error.Message; }
        if (failure != null)
        {
            try { game = await Task.Run(() => updater.Installed()); }
            catch (IOException) { game = null; }
            catch (UnauthorizedAccessException) { game = null; }
            Report((game == null ? "Could not install the game. " : "Update unavailable. You can play the installed version. ") + failure);
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
