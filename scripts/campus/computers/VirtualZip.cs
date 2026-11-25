using System;
using System.IO;
using System.IO.Compression;
using Godot;
using Dictionary = Godot.Collections.Dictionary;

[GlobalClass]
public partial class VirtualZip : RefCounted
{
    private const int EntryLimit = 512;
    private const int ArchiveLimit = 8 * 1024 * 1024;
    private const int ExpandedLimit = 32 * 1024 * 1024;

    public byte[] Pack(Dictionary files)
    {
        if (files.Count > EntryLimit)
            return Array.Empty<byte>();

        try
        {
            using var output = new MemoryStream();
            using (var archive = new ZipArchive(output, ZipArchiveMode.Create, leaveOpen: true))
            {
                int totalBytes = 0;
                foreach (var file in files)
                {
                    string name = file.Key.AsString();
                    byte[] bytes = file.Value.AsByteArray();
                    totalBytes += bytes.Length;
                    if (totalBytes > ExpandedLimit)
                        return Array.Empty<byte>();

                    var entry = archive.CreateEntry(name, CompressionLevel.Fastest);
                    entry.LastWriteTime = new DateTimeOffset(1980, 1, 1, 0, 0, 0, TimeSpan.Zero);
                    if (!name.EndsWith('/'))
                    {
                        using var stream = entry.Open();
                        stream.Write(bytes);
                    }
                }
            }
            return output.Length <= ArchiveLimit ? output.ToArray() : Array.Empty<byte>();
        }
        catch (IOException)
        {
            return Array.Empty<byte>();
        }
    }

    public Dictionary Unpack(byte[] bytes, int capacity)
    {
        try
        {
            using var input = new MemoryStream(bytes, writable: false);
            using var archive = new ZipArchive(input, ZipArchiveMode.Read);
            var files = new Dictionary();
            if (archive.Entries.Count > EntryLimit)
                return Failure("The ZIP contains too many items.");

            long remaining = Math.Clamp(capacity, 0, ExpandedLimit);
            foreach (var entry in archive.Entries)
            {
                string name = entry.FullName;
                if (!SafeName(name) || files.ContainsKey(name))
                    return Failure("The ZIP contains an invalid or duplicate path.");
                if (entry.Length < 0 || entry.Length > remaining)
                    return Failure("The extracted ZIP exceeds the available space.");
                remaining -= entry.Length;
                bool folder = name.EndsWith('/');
                if (folder && entry.Length != 0)
                    return Failure("The ZIP contains an invalid folder entry.");

                byte[] data = new byte[(int)entry.Length];
                using var stream = entry.Open();
                stream.ReadExactly(data);
                if (stream.ReadByte() != -1)
                    return Failure("The ZIP entry exceeds its declared size.");
                files[name] = data;
            }
            return new Dictionary { ["files"] = files };
        }
        catch (Exception error) when (error is IOException or InvalidDataException or NotSupportedException)
        {
            return Failure("This ZIP is damaged or uses an unsupported compression method.");
        }
    }

    private static bool SafeName(string name)
    {
        if (name.Length is 0 or > 96 || name.Contains('\\') || name.Contains(':'))
            return false;
        foreach (var component in name.TrimEnd('/').Split('/'))
        {
            if (component is "" or "." or ".." || component.StartsWith('.') ||
                component != component.Trim() || component.Length > 32)
                return false;
        }
        return true;
    }

    private static Dictionary Failure(string message) => new() { ["error"] = message };
}
