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
    private const int Limit = 8 * 1024 * 1024;
    private static readonly SemaphoreSlim MsiReader = new(1);
    private static readonly HashSet<string> MsiUnsupported = new(StringComparer.OrdinalIgnoreCase)
    {
        "CustomAction", "ServiceInstall", "ServiceControl", "Registry", "RemoveRegistry", "Environment",
        "SelfReg", "TypeLib", "Class", "AppId", "ProgId", "Extension", "Verb", "MoveFile", "DuplicateFile",
        "ODBCDataSource", "ODBCDriver", "IniFile", "RemoveIniFile", "MsiAssembly", "LockPermissions", "MsiLockPermissionsEx"
    };

    public Result Read(string format, byte[] bytes)
    {
        if (bytes.Length is < 64 or > Limit) return Error("The package is outside the 8 MiB import limit.");
        try
        {
            byte[] executable = format switch
            {
                "msix" => ReadMsix(bytes),
                "msi" when OperatingSystem.IsWindows() => ReadMsi(bytes),
                "msi" => throw new InvalidDataException("Reading MSI packages requires Windows."),
                _ => throw new InvalidDataException("This package format has no portable install path.")
            };
            var metadata = new WindowsExecutableInspector().Inspect(executable);
            if (metadata.ContainsKey("error") || metadata["kind"].AsString() != "Desktop application" ||
                metadata["runtime"].AsString() != "Native entry point" ||
                metadata["architecture"].AsString() is not ("x64" or "x86"))
                return Error("The package must contain a standalone x86 or x64 native desktop executable.");
            return new Result { ["image"] = executable, ["architecture"] = metadata["architecture"] };
        }
        catch (InvalidDataException e) { return Error(e.Message); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or XmlException or NotSupportedException or ArgumentException)
        {
            return Error("The Windows package could not be read safely.");
        }
    }

    private static byte[] ReadMsix(byte[] bytes)
    {
        using var input = new MemoryStream(bytes, writable: false);
        using var archive = new ZipArchive(input, ZipArchiveMode.Read);
        if (archive.Entries.Count is < 2 or > 64) throw new InvalidDataException("The MSIX has an unsupported file layout.");
        var files = new Dictionary<string, ZipArchiveEntry>(StringComparer.OrdinalIgnoreCase);
        int size = 0;
        foreach (var file in archive.Entries)
        {
            var name = file.FullName.TrimEnd('/');
            if (!SafePath(name) || file.Length < 0 || file.Length > Limit - size || !files.TryAdd(name, file))
                throw new InvalidDataException("The MSIX contains an invalid path or exceeds the expanded-size limit.");
            size += (int)file.Length;
        }
        if (!files.TryGetValue("AppxManifest.xml", out var manifest) || manifest.Length is < 1 or > 65536)
            throw new InvalidDataException("The MSIX needs a readable AppxManifest.xml.");
        using var xml = XmlReader.Create(manifest.Open(), new XmlReaderSettings
        {
            DtdProcessing = DtdProcessing.Prohibit,
            XmlResolver = null,
            MaxCharactersInDocument = 65536
        });
        var package = XDocument.Load(xml).Root;
        if (package == null || package.Name.LocalName != "Package" ||
            package.Descendants().Any(e => e.Name.LocalName is "PackageDependency" or "HostRuntimeDependency" or
                "MainPackageDependency" or "Extension" or "ExternalLocation"))
            throw new InvalidDataException("This MSIX needs Windows package dependencies or registration.");
        var apps = package.Elements().Where(e => e.Name.LocalName == "Applications")
            .SelectMany(e => e.Elements().Where(a => a.Name.LocalName == "Application")).ToArray();
        if (apps.Length != 1) throw new InvalidDataException("A portable MSIX must declare exactly one desktop application.");
        string entry = ((string?)apps[0].Attribute("Executable") ?? "").Replace((char)92, '/');
        string kind = (string?)apps[0].Attribute("EntryPoint") ?? "";
        if (!SafePath(entry) || !entry.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ||
            (kind.Length != 0 && kind != "Windows.FullTrustApplication") ||
            !files.TryGetValue(entry, out var program) || program.Length < 64)
            throw new InvalidDataException("This MSIX has no compatible standalone desktop entry point.");
        var branding = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            entry, "AppxManifest.xml", "AppxBlockMap.xml", "AppxSignature.p7x", "[Content_Types].xml", "AppxMetadata/CodeIntegrity.cat"
        };
        foreach (var attr in package.Descendants().SelectMany(e => e.Attributes()))
            if (attr.Name.LocalName.EndsWith("Logo", StringComparison.Ordinal))
                branding.Add(attr.Value.Replace((char)92, '/'));
        foreach (var element in package.Descendants().Where(e => e.Name.LocalName == "Logo"))
            branding.Add(element.Value.Replace((char)92, '/'));
        if (files.Any(pair => !pair.Value.FullName.EndsWith('/') && !branding.Contains(pair.Key)))
            throw new InvalidDataException("This MSIX needs extra packaged files. The current runtime installs single-file apps.");
        using var stream = program.Open();
        var payload = new byte[(int)program.Length];
        stream.ReadExactly(payload);
        if (stream.ReadByte() != -1) throw new InvalidDataException("The MSIX entry size does not match its header.");
        return payload;
    }

    private static bool SafePath(string path) => path.Length is > 0 and <= 180 &&
        path.Split('/').All(part => part.Length is > 0 and <= 64 && part is not ("." or "..") &&
            part == part.Trim() && !part.EndsWith('.') &&
            part.All(c => char.IsAsciiLetterOrDigit(c) || c is '_' or '-' or '.' or ' ' or '[' or ']'));

    private static byte[] ReadMsi(byte[] input)
    {
        if (!MsiReader.Wait(0)) throw new InvalidDataException("Another MSI package is being read.");
        DirectoryInfo? directory = null;
        try
        {
            directory = Directory.CreateTempSubdirectory("LabVoltMsi-");
            var source = Path.Combine(directory.FullName, "package.msi");
            File.WriteAllBytes(source, input);
            Require(MsiOpenDatabase(source, IntPtr.Zero, out uint db));
            try
            {
                using (var tables = new MsiQuery(db, "SELECT `Name` FROM `_Tables`"))
                    for (uint row = tables.Next(); row != 0; row = tables.Next())
                        if (MsiUnsupported.Contains(Text(row, 1)))
                            throw new InvalidDataException("This MSI includes Windows installation actions. Only files-only packages are supported.");

                string id;
                int length, sequence;
                using (var files = new MsiQuery(db, "SELECT `File`, `FileName`, `FileSize`, `Sequence` FROM `File`"))
                {
                    uint row = files.Next();
                    if (row == 0) throw new InvalidDataException("The MSI has no application payload.");
                    id = Text(row, 1);
                    string path = Text(row, 2).Split('|').Last();
                    length = MsiRecordGetInteger(row, 3);
                    sequence = MsiRecordGetInteger(row, 4);
                    if (files.Next() != 0 || !SafePath(id) || id.Contains('/') || !SafePath(path) || path.Contains('/') ||
                        !path.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) || length is < 64 or > Limit || sequence < 1)
                        throw new InvalidDataException("The MSI must contain exactly one standalone executable.");
                }

                string cabinet;
                using (var media = new MsiQuery(db, "SELECT `Cabinet`, `LastSequence` FROM `Media`"))
                {
                    uint row = media.Next();
                    if (row == 0) throw new InvalidDataException("The MSI does not have embedded installation media.");
                    cabinet = Text(row, 1);
                    if (MsiRecordGetInteger(row, 2) != sequence || media.Next() != 0 ||
                        !cabinet.StartsWith('#') || !SafePath(cabinet[1..]) || cabinet.Contains('/'))
                        throw new InvalidDataException("The MSI must use one embedded cabinet.");
                }

                var cabPath = Path.Combine(directory.FullName, "payload.cab");
                using (var stream = new MsiQuery(db, "SELECT `Data` FROM `_Streams` WHERE `Name` = '" + cabinet[1..] + "'"))
                {
                    uint row = stream.Next();
                    if (row == 0) throw new InvalidDataException("The embedded MSI cabinet is missing.");
                    var data = new byte[Limit];
                    uint size = (uint)data.Length;
                    Require(MsiRecordReadStream(row, 1, data, ref size));
                    if (size < 36 || stream.Next() != 0) throw new InvalidDataException("The embedded MSI cabinet is invalid.");
                    using var target = File.Create(cabPath);
                    target.Write(data, 0, (int)size);
                }
                return ExtractSingleCab(cabPath, Path.Combine(directory.FullName, "program.exe"), id, length);
            }
            finally { MsiCloseHandle(db); }
        }
        finally
        {
            try { directory?.Delete(recursive: true); }
            finally { MsiReader.Release(); }
        }
    }

    private static byte[] ExtractSingleCab(string cabinet, string destination, string expected, int expectedSize)
    {
        if (destination.Length >= 260) throw new InvalidDataException("The Windows temporary path is too long to read MSI packages.");
        int found = 0;
        bool reject = false;
        uint Callback(IntPtr _, uint notice, IntPtr param, IntPtr unused)
        {
            if (notice == 0x12) { reject = true; return 13; }
            if (notice != 0x11) return 0;
            var file = Marshal.PtrToStructure<CabEntry>(param);
            if (++found != 1 || file.Size != expectedSize || Marshal.PtrToStringUni(file.Name) != expected)
            {
                reject = true;
                return 0;
            }
            file.Target = destination;
            Marshal.StructureToPtr(file, param, false);
            return 1;
        }
        if (!SetupIterateCabinet(cabinet, 0, Callback, IntPtr.Zero) || reject || found != 1 ||
            !File.Exists(destination) || new FileInfo(destination).Length != expectedSize)
            throw new InvalidDataException("The cabinet must contain only the application declared by the MSI.");
        return File.ReadAllBytes(destination);
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
