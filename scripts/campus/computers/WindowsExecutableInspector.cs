using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Security.Cryptography;
using System.Xml;
using System.Xml.Linq;
using System.Reflection.PortableExecutable;
using Godot;

public partial class WindowsExecutableInspector : RefCounted
{
    private const int MaxExecutableBytes = 8 * 1024 * 1024;

    public Godot.Collections.Dictionary Inspect(byte[] executable)
    {
        if (executable.Length < 64 || executable.Length > MaxExecutableBytes)
            return Failure("The file size is outside the Windows executable preview limit.");

        try
        {
            using var file = new MemoryStream(executable, writable: false);
            using var pe = new PEReader(file);
            var headers = pe.PEHeaders;
            var image = headers.PEHeader;
            if (image == null)
                return Failure("The file does not contain a Windows PE image.");

            if ((headers.CoffHeader.Characteristics & Characteristics.ExecutableImage) == 0)
                return Failure("The file is an object file or library.");
            if ((headers.CoffHeader.Characteristics & Characteristics.Dll) != 0)
                return Failure("A Windows DLL cannot run as an application.");
            if (image.Subsystem is not (Subsystem.WindowsGui or Subsystem.WindowsCui))
                return Failure("The file is not a Windows desktop or console application.");

            int entrySection = headers.GetContainingSectionIndex(image.AddressOfEntryPoint);
            if (entrySection < 0 || image.AddressOfEntryPoint == 0 ||
                (headers.SectionHeaders[entrySection].SectionCharacteristics & SectionCharacteristics.MemExecute) == 0)
                return Failure("The executable does not have a valid entry point.");
            foreach (var section in headers.SectionHeaders)
            {
                if (section.SizeOfRawData < 0 || section.PointerToRawData < 0 ||
                    (long)section.PointerToRawData + section.SizeOfRawData > executable.Length)
                    return Failure("The executable contains an incomplete section.");
            }

            string architecture = headers.CoffHeader.Machine switch
            {
                Machine.Amd64 => "x64",
                Machine.I386 => "x86",
                Machine.Arm64 => "ARM64",
                _ => headers.CoffHeader.Machine.ToString(),
            };
            return new Godot.Collections.Dictionary
            {
                ["architecture"] = architecture,
                ["sha256"] = Digest(executable),
                ["kind"] = image.Subsystem == Subsystem.WindowsGui ? "Desktop application" : "Console application",
                ["runtime"] = headers.CorHeader == null ? "Native entry point" : ".NET assembly",
            };
        }
        catch (Exception error) when (error is BadImageFormatException or IOException
            or ArgumentException or OverflowException or InvalidOperationException)
        {
            return Failure("The file has a malformed Windows executable header.");
        }
    }

    public Godot.Collections.Dictionary InspectPackage(string extension, byte[] bytes)
    {
        if (bytes.Length < 64 || bytes.Length > MaxExecutableBytes)
            return Failure("The file size is outside the Windows package preview limit.");

        if (extension == "msi")
        {
            // MSI installers use an OLE compound file. This identifies the container only.
            ReadOnlySpan<byte> compoundSignature = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
            if (bytes.Length < 512 || !bytes.AsSpan().StartsWith(compoundSignature))
                return Failure("The Windows Installer container header is damaged.");
            return new Godot.Collections.Dictionary
            {
                ["kind"] = "Windows Installer (MSI container)",
                ["sha256"] = Digest(bytes),
            };
        }
        if (extension is not ("msix" or "msixbundle"))
            return Failure("This Windows package format is unsupported.");

        bool bundle = extension == "msixbundle";
        const int maxManifestBytes = 256 * 1024;
        string manifestName = bundle ? "AppxMetadata/AppxBundleManifest.xml" : "AppxManifest.xml";
        try
        {
            using var stream = new MemoryStream(bytes, writable: false);
            using var archive = new ZipArchive(stream, ZipArchiveMode.Read);
            var matches = archive.Entries.Where(entry =>
                string.Equals(entry.FullName, manifestName, StringComparison.OrdinalIgnoreCase)).Take(2).ToArray();
            if (matches.Length != 1 || matches[0].Length is < 1 or > maxManifestBytes)
                return Failure("The package needs one complete, supported manifest.");

            using var entryStream = matches[0].Open();
            var data = new byte[(int)matches[0].Length];
            entryStream.ReadExactly(data);
            if (entryStream.ReadByte() != -1)
                return Failure("The package manifest size does not match its header.");

            using var manifest = new MemoryStream(data, writable: false);
            using var reader = XmlReader.Create(manifest, new XmlReaderSettings
            {
                DtdProcessing = DtdProcessing.Prohibit,
                XmlResolver = null,
                MaxCharactersInDocument = maxManifestBytes,
            });
            var root = XElement.Load(reader);
            if (root.Name.LocalName != (bundle ? "Bundle" : "Package"))
                return Failure("The manifest does not match this Windows package type.");

            var identity = root.Element(root.Name.Namespace + "Identity");
            string name = Field(identity, "Name");
            string publisher = Field(identity, "Publisher");
            string version = Field(identity, "Version");
            if (name.Length == 0 || publisher.Length == 0 || !Version.TryParse(version, out var parsed) || parsed.Revision < 0)
                return Failure("The package manifest is missing its name, publisher or four-part version.");

            string architecture = bundle ? string.Join(", ", root.Element(root.Name.Namespace + "Packages")?
                .Elements(root.Name.Namespace + "Package").Select(package => Field(package, "Architecture"))
                .Where(value => value.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase).Take(8)
                ?? Enumerable.Empty<string>()) : Field(identity, "ProcessorArchitecture");
            return new Godot.Collections.Dictionary
            {
                ["kind"] = bundle ? "MSIX bundle" : "MSIX package",
                ["name"] = name,
                ["publisher"] = publisher,
                ["version"] = version,
                ["architecture"] = architecture,
                ["sha256"] = Digest(bytes),
            };
        }
        catch (Exception error) when (error is IOException or InvalidDataException or XmlException
            or ArgumentException or InvalidOperationException or NotSupportedException)
        {
            return Failure("The Windows package could not be inspected.");
        }
    }

    private static string Field(XElement element, string name) =>
        string.Concat(((string)element?.Attribute(name) ?? "").Where(character => !char.IsControl(character)).Take(256)).Trim();

    private static string Digest(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();

    private static Godot.Collections.Dictionary Failure(string message)
    {
        return new Godot.Collections.Dictionary { ["error"] = message };
    }
}
