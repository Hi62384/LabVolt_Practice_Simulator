#nullable enable
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Xml;
using System.Xml.Linq;
using Godot;
using Result = Godot.Collections.Dictionary;

public partial class WindowsPortablePackage : RefCounted
{
    private static readonly SemaphoreSlim MsiReader = new(1);

    private const int ImportLimit = 8 * 1024 * 1024;

    public Result Read(string format, byte[] bytes, string requestedEntry, bool pack)
    {
        if (bytes.Length is < 64 or > ImportLimit) return Error("The package is outside the 8 MiB import limit.");
        try
        {
            string declaredEntry = "";
            var layout = format switch
            {
                "msix" => ReadMsix(bytes, out declaredEntry),
                "msi" when OperatingSystem.IsWindows() => ReadMsi(bytes),
                "msi" => throw new InvalidDataException("Reading MSI packages requires Windows."),
                _ => throw new InvalidDataException("This package format has no portable install path.")
            };
            var inspector = new WindowsExecutableInspector();
            var entries = new Godot.Collections.Array<string>();
            foreach (var pair in layout.Files.OrderBy(pair => pair.Key, StringComparer.OrdinalIgnoreCase))
            {
                if (!pair.Key.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ||
                    (declaredEntry.Length != 0 && pair.Key != declaredEntry)) continue;
                var metadata = inspector.Inspect(pair.Value);
                if (!metadata.ContainsKey("error") && metadata["kind"].AsString() == "Desktop application" &&
                    metadata["runtime"].AsString() == "Native entry point" &&
                    metadata["architecture"].AsString() is "x64" or "x86")
                    entries.Add(pair.Key);
            }
            if (entries.Count == 0) return Error("The package has no compatible x86 or x64 native desktop executable.");
            string entry = requestedEntry.Length == 0 ? entries[0] : requestedEntry;
            if (!entries.Contains(entry)) return Error("Choose an executable from this package.");
            var result = new Result { ["entries"] = entries, ["file_count"] = layout.Files.Count,
                ["entry"] = entry, ["image"] = layout.Files[entry] };
            if (pack) result["bundle"] = CampusWindowsBundle.Pack(entry, layout);
            return result;
        }
        catch (InvalidDataException e) { return Error(e.Message); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or XmlException or NotSupportedException or ArgumentException)
        {
            return Error("The Windows package could not be read safely.");
        }
    }

    private static CampusWindowsBundle.Layout ReadMsix(byte[] bytes, out string entry)
    {
        using var input = new MemoryStream(bytes, writable: false);
        using var archive = new ZipArchive(input, ZipArchiveMode.Read);
        if (archive.Entries.Count is < 2 or > CampusWindowsBundle.FileLimit + 32)
            throw new InvalidDataException("The MSIX has an unsupported file count.");
        var files = new Dictionary<string, ZipArchiveEntry>(StringComparer.OrdinalIgnoreCase);
        foreach (var file in archive.Entries)
        {
            var name = file.FullName.TrimEnd('/');
            if (!CampusWindowsBundle.SafePath(name) || file.Length < 0 || !files.TryAdd(name, file))
                throw new InvalidDataException("The MSIX contains an invalid or duplicate path.");
        }
        if (!files.TryGetValue("AppxManifest.xml", out var manifest) || manifest.Length is < 1 or > 65536)
            throw new InvalidDataException("The MSIX needs a readable AppxManifest.xml.");
        using var manifestStream = manifest.Open();
        using var xml = XmlReader.Create(manifestStream, new XmlReaderSettings
        {
            DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null, MaxCharactersInDocument = 65536
        });
        var package = XDocument.Load(xml).Root;
        if (package == null || package.Name.LocalName != "Package" ||
            package.Descendants().Any(e => e.Name.LocalName is "PackageDependency" or "HostRuntimeDependency" or
                "MainPackageDependency" or "OptionalPackage" or "ExternalLocation"))
            throw new InvalidDataException("This MSIX requires other Windows packages or external files.");
        var apps = package.Elements().Where(e => e.Name.LocalName == "Applications")
            .SelectMany(e => e.Elements().Where(a => a.Name.LocalName == "Application")).ToArray();
        if (apps.Length != 1) throw new InvalidDataException("An MSIX must declare one desktop application.");
        entry = ((string?)apps[0].Attribute("Executable") ?? "").Replace((char)92, '/');
        string kind = (string?)apps[0].Attribute("EntryPoint") ?? "";
        if (!CampusWindowsBundle.SafePath(entry) || !entry.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ||
            (kind.Length != 0 && kind != "Windows.FullTrustApplication") ||
            apps[0].Attributes().Any(a => a.Name.LocalName == "RuntimeBehavior" && a.Value == "windowsApp") ||
            !files.TryGetValue(entry, out var program) || program.Length < 64)
            throw new InvalidDataException("This MSIX has no compatible desktop entry point.");
        entry = program.FullName;
        var metadata = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "AppxManifest.xml", "AppxBlockMap.xml", "AppxSignature.p7x", "[Content_Types].xml", "AppxMetadata/CodeIntegrity.cat"
        };
        var layout = new CampusWindowsBundle.Layout();
        int remaining = CampusWindowsBundle.PayloadLimit;
        foreach (var file in files.Values)
        {
            if (metadata.Contains(file.FullName) || file.FullName.EndsWith('/')) continue;
            if (file.Length > remaining) throw new InvalidDataException("The MSIX expands beyond 32 MiB.");
            using var stream = file.Open();
            var payload = new byte[(int)file.Length];
            stream.ReadExactly(payload);
            if (stream.ReadByte() != -1) throw new InvalidDataException("The MSIX file size does not match its header.");
            layout.Add(file.FullName, payload);
            remaining -= payload.Length;
        }
        return layout;
    }

    private sealed record MsiFile(string Id, string Path, int Length, int Sequence);
    private sealed record MsiDirectory(string Parent, string Name);

    private static CampusWindowsBundle.Layout ReadMsi(byte[] input)
    {
        if (!MsiReader.Wait(0)) throw new InvalidDataException("Another MSI package is being read.");
        DirectoryInfo? directory = null;
        try
        {
            directory = Directory.CreateTempSubdirectory("LabVoltMsi-");
            var source = Path.Combine(directory.FullName, "package.msi");
            File.WriteAllBytes(source, input);
            Require(MsiOpenDatabase(source, IntPtr.Zero, out uint db));
            try { return ReadMsiLayout(db, directory.FullName); }
            finally { MsiCloseHandle(db); }
        }
        finally
        {
            try { directory?.Delete(recursive: true); }
            finally { MsiReader.Release(); }
        }
    }

    private static CampusWindowsBundle.Layout ReadMsiLayout(uint db, string scratch)
    {
        var directories = new Dictionary<string, MsiDirectory>(StringComparer.Ordinal);
        using (var query = new MsiQuery(db, "SELECT `Directory`, `Directory_Parent`, `DefaultDir` FROM `Directory`"))
            for (uint row = query.Next(); row != 0; row = query.Next())
            {
                if (directories.Count >= 512 || !directories.TryAdd(Text(row, 1), new MsiDirectory(Text(row, 2), Text(row, 3))))
                    throw new InvalidDataException("The MSI has an unsupported directory table.");
            }
        var components = new Dictionary<string, string>(StringComparer.Ordinal);
        using (var query = new MsiQuery(db, "SELECT `Component`, `Directory_` FROM `Component`"))
            for (uint row = query.Next(); row != 0; row = query.Next())
            {
                if (components.Count >= 512 || !components.TryAdd(Text(row, 1), Text(row, 2)))
                    throw new InvalidDataException("The MSI has an unsupported component table.");
            }
        var files = new List<MsiFile>();
        var sequences = new HashSet<int>();
        int remaining = CampusWindowsBundle.PayloadLimit;
        using (var query = new MsiQuery(db, "SELECT `File`, `Component_`, `FileName`, `FileSize`, `Sequence`, `Attributes` FROM `File`"))
            for (uint row = query.Next(); row != 0; row = query.Next())
            {
                string id = Text(row, 1);
                string name = Text(row, 3).Split('|').Last();
                int length = MsiRecordGetInteger(row, 4), sequence = MsiRecordGetInteger(row, 5);
                int attributes = MsiRecordGetInteger(row, 6);
                if (files.Count >= CampusWindowsBundle.FileLimit || length < 0 || length > remaining || sequence < 1 ||
                    !sequences.Add(sequence) || !CampusWindowsBundle.SafePath(id) || id.Contains('/') || name.Contains('/') ||
                    !CampusWindowsBundle.SafePath(name) || !components.TryGetValue(Text(row, 2), out var folder) ||
                    (attributes != int.MinValue && (attributes & 8192) != 0))
                    throw new InvalidDataException("The MSI has an invalid file or references external installation media.");
                string parent = MsiFolder(folder, directories);
                files.Add(new MsiFile(id, parent.Length == 0 ? name : parent + "/" + name, length, sequence));
                remaining -= length;
            }
        if (files.Count == 0) throw new InvalidDataException("The MSI has no application files.");

        var layout = new CampusWindowsBundle.Layout();
        int previous = 0;
        using (var media = new MsiQuery(db, "SELECT `Cabinet`, `LastSequence` FROM `Media` ORDER BY `DiskId`"))
            for (uint row = media.Next(); row != 0; row = media.Next())
            {
                string cabinet = Text(row, 1);
                int last = MsiRecordGetInteger(row, 2);
                if (last <= previous) throw new InvalidDataException("The MSI media sequence is invalid.");
                var expected = files.Where(file => file.Sequence > previous && file.Sequence <= last)
                    .ToDictionary(file => file.Id, StringComparer.Ordinal);
                previous = last;
                if (expected.Count == 0) continue;
                if (!cabinet.StartsWith('#') || cabinet.Length is < 2 or > 73 ||
                    !cabinet.Skip(1).All(c => char.IsAsciiLetterOrDigit(c) || c is '.' or '_' or '-'))
                    throw new InvalidDataException("The MSI requires an external or unsupported cabinet.");
                var cabPath = Path.Combine(scratch, "payload.cab");
                using (var stream = new MsiQuery(db, "SELECT `Data` FROM `_Streams` WHERE `Name` = '" + cabinet[1..] + "'"))
                {
                    uint item = stream.Next();
                    if (item == 0) throw new InvalidDataException("An embedded MSI cabinet is missing.");
                    var data = new byte[ImportLimit];
                    uint size = (uint)data.Length;
                    Require(MsiRecordReadStream(item, 1, data, ref size));
                    if (size < 36 || stream.Next() != 0) throw new InvalidDataException("An embedded MSI cabinet is invalid.");
                    using var target = File.Create(cabPath);
                    target.Write(data, 0, (int)size);
                }
                ExtractCab(cabPath, scratch, expected, layout);
            }
        if (layout.Files.Count != files.Count) throw new InvalidDataException("The MSI package has missing files.");
        return layout;
    }

    private static string MsiFolder(string id, Dictionary<string, MsiDirectory> directories)
    {
        var names = new List<string>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        while (id.Length != 0)
        {
            if (seen.Count >= 24 || !seen.Add(id) || !directories.TryGetValue(id, out var directory))
                throw new InvalidDataException("The MSI directory tree is invalid.");
            if (id == "TARGETDIR") break;
            if (id is not ("ProgramFilesFolder" or "ProgramFiles64Folder"))
            {
                string name = directory.Name.Split(':')[0].Split('|').Last();
                if (name != ".")
                {
                    if (name.Contains('/') || !CampusWindowsBundle.SafePath(name))
                        throw new InvalidDataException("The MSI directory names are not portable.");
                    names.Add(name);
                }
            }
            id = directory.Parent;
        }
        names.Reverse();
        return string.Join("/", names);
    }

    private static void ExtractCab(string cabinet, string scratch, Dictionary<string, MsiFile> expected,
        CampusWindowsBundle.Layout layout)
    {
        var found = new Dictionary<string, string>(StringComparer.Ordinal);
        bool reject = false;
        uint Callback(IntPtr _, uint notice, IntPtr param, IntPtr unused)
        {
            if (notice == 0x12) { reject = true; return 13; }
            if (notice != 0x11) return 0;
            var file = Marshal.PtrToStructure<CabEntry>(param);
            var name = Marshal.PtrToStringUni(file.Name);
            if (name == null || !expected.TryGetValue(name, out var declared) ||
                file.Size != declared.Length || found.ContainsKey(name))
            {
                reject = true;
                return 0;
            }
            var destination = Path.Combine(scratch, "part-" + found.Count);
            if (destination.Length >= 260) { reject = true; return 0; }
            found.Add(name, destination);
            file.Target = destination;
            Marshal.StructureToPtr(file, param, false);
            return 1;
        }
        if (!SetupIterateCabinet(cabinet, 0, Callback, IntPtr.Zero) || reject || found.Count != expected.Count)
            throw new InvalidDataException("The cabinet contents differ from the MSI file table.");
        foreach (var pair in found)
        {
            var declared = expected[pair.Key];
            if (new FileInfo(pair.Value).Length != declared.Length)
                throw new InvalidDataException("An extracted MSI file has the wrong size.");
            layout.Add(declared.Path, File.ReadAllBytes(pair.Value));
            File.Delete(pair.Value);
        }
    }

    private sealed class MsiQuery : IDisposable
    {
        private uint view;
        private uint row;
        public MsiQuery(uint db, string query)
        {
            uint result = MsiDatabaseOpenView(db, query, out view);
            if (result == 0) result = MsiViewExecute(view, 0);
            if (result != 0) { Dispose(); Require(result); }
        }

        public uint Next()
        {
            if (row != 0) MsiCloseHandle(row);
            uint code = MsiViewFetch(view, out row);
            if (code == 259) return 0;
            Require(code);
            return row;
        }

        public void Dispose()
        {
            if (row != 0) MsiCloseHandle(row);
            if (view != 0) MsiCloseHandle(view);
        }
    }

    private static string Text(uint record, uint field)
    {
        uint length = 260;
        var text = new System.Text.StringBuilder((int)length);
        Require(MsiRecordGetString(record, field, text, ref length));
        return text.ToString();
    }
    private static void Require(uint result)
    {
        if (result != 0) throw new InvalidDataException("The MSI layout is unsupported or damaged (Windows code " + result + ").");
    }
    private static Result Error(string text) => new() { ["error"] = text };

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct CabEntry
    {
        public IntPtr Name;
        public uint Size, Error;
        public ushort Date, Time, Attributes;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string Target;
    }
    private delegate uint CabCallback(IntPtr context, uint notice, IntPtr first, IntPtr second);
    [DllImport("setupapi.dll", CharSet=CharSet.Unicode)] private static extern bool SetupIterateCabinet(string cabinet, uint zero, CabCallback callback, IntPtr context);
    [DllImport("msi.dll", CharSet=CharSet.Unicode)] private static extern uint MsiOpenDatabase(string path, IntPtr persist, out uint handle);
    [DllImport("msi.dll", CharSet=CharSet.Unicode)] private static extern uint MsiDatabaseOpenView(uint db, string query, out uint view);
    [DllImport("msi.dll")] private static extern uint MsiCloseHandle(uint handle);
    [DllImport("msi.dll")] private static extern uint MsiViewExecute(uint view, uint parameters);
    [DllImport("msi.dll")] private static extern uint MsiViewFetch(uint view, out uint row);
    [DllImport("msi.dll")] private static extern int MsiRecordGetInteger(uint row, uint field);
    [DllImport("msi.dll", CharSet=CharSet.Unicode)] private static extern uint MsiRecordGetString(uint row, uint field, System.Text.StringBuilder text, ref uint size);
    [DllImport("msi.dll")] private static extern uint MsiRecordReadStream(uint row, uint field, [Out] byte[] bytes, ref uint size);
}
