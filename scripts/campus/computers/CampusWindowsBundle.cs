using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

internal static class CampusWindowsBundle
{
    internal const string Filename = "Application.campuswin";
    internal const int PayloadLimit = 32 * 1024 * 1024;
    internal const int FileLimit = 256;
    internal const int PathLimit = 180;
    internal const int WireLimit = PayloadLimit + FileLimit * (PathLimit + 6) + PathLimit + 8;

    internal sealed class Layout
    {
        internal readonly Dictionary<string, byte[]> Files = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        private readonly Dictionary<string, string> directories = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        private readonly HashSet<string> paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        private int bytes;

        internal void Add(string name, byte[] data)
        {
            if (!SafePath(name) || Files.Count >= FileLimit || data.Length > PayloadLimit - bytes ||
                directories.ContainsKey(name) || !paths.Add(name))
                throw new InvalidDataException("The application has conflicting paths or exceeds the payload limit.");
            for (int separator = name.IndexOf('/'); separator >= 0; separator = name.IndexOf('/', separator + 1))
            {
                string parent = name.Substring(0, separator);
                string previous;
                if (paths.Contains(parent) || (directories.TryGetValue(parent, out previous) && previous != parent))
                    throw new InvalidDataException("The application has conflicting file and folder names.");
                directories[parent] = parent;
            }
            bytes += data.Length;
            Files.Add(name, data);
        }
    }

    internal static bool SafePath(string path)
    {
        if (path.Length == 0 || path.Length > PathLimit) return false;
        string[] parts = path.Split('/');
        if (parts.Length > 12) return false;
        foreach (string part in parts)
        {
            if (part.Length == 0 || part.Length > 80 || part[0] == ' ' ||
                part[part.Length - 1] == '.' || part[part.Length - 1] == ' ') return false;
            foreach (char c in part)
                if (!(c >= '0' && c <= '9' || c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' ||
                      c == '_' || c == '-' || c == '.' || c == ' ' || c == '[' || c == ']' ||
                      c == '(' || c == ')' || c == '\'' || c == '+')) return false;
            string device = part.Split('.')[0].TrimEnd().ToUpperInvariant();
            if (device == "CON" || device == "PRN" || device == "AUX" || device == "NUL" ||
                (device.Length == 4 && (device.StartsWith("COM", StringComparison.Ordinal) ||
                 device.StartsWith("LPT", StringComparison.Ordinal)) && char.IsDigit(device[3]))) return false;
        }
        return true;
    }

    internal static byte[] Pack(string entry, Layout layout)
    {
        ValidateEntry(entry, layout);
        var names = new List<string>(layout.Files.Keys);
        names.Sort(StringComparer.Ordinal);
        using (var buffer = new MemoryStream())
        using (var writer = new BinaryWriter(buffer))
        {
            writer.Write(0x4C564231);
            WritePath(writer, entry);
            writer.Write((ushort)names.Count);
            foreach (string name in names)
            {
                byte[] data = layout.Files[name];
                WritePath(writer, name);
                writer.Write(data.Length);
                writer.Write(data);
            }
            return buffer.ToArray();
        }
    }

    internal static Layout Unpack(byte[] payload, out string entry)
    {
        if (payload.Length > WireLimit) throw new InvalidDataException("Application bundle is too large.");
        using (var reader = new BinaryReader(new MemoryStream(payload, false)))
        {
            if (reader.ReadInt32() != 0x4C564231) throw new InvalidDataException("Invalid application bundle.");
            entry = ReadPath(reader);
            int count = reader.ReadUInt16();
            if (count < 1 || count > FileLimit) throw new InvalidDataException("Invalid application file count.");
            var layout = new Layout();
            int room = PayloadLimit;
            for (int i = 0; i < count; i++)
            {
                string name = ReadPath(reader);
                int length = reader.ReadInt32();
                if (length < 0 || length > room || length > payload.Length - reader.BaseStream.Position)
                    throw new InvalidDataException("Invalid application file size.");
                layout.Add(name, reader.ReadBytes(length));
                room -= length;
            }
            if (reader.BaseStream.Position != payload.Length) throw new InvalidDataException("Unexpected application data.");
            ValidateEntry(entry, layout);
            return layout;
        }
    }

    private static void ValidateEntry(string entry, Layout layout)
    {
        byte[] image;
        if (!entry.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ||
            !layout.Files.TryGetValue(entry, out image) || image.Length < 64 || image[0] != 'M' || image[1] != 'Z')
            throw new InvalidDataException("The application executable is missing.");
    }

    private static void WritePath(BinaryWriter writer, string path)
    {
        writer.Write((ushort)path.Length);
        writer.Write(Encoding.ASCII.GetBytes(path));
    }

    private static string ReadPath(BinaryReader reader)
    {
        int length = reader.ReadUInt16();
        if (length < 1 || length > PathLimit) throw new InvalidDataException("Invalid application path length.");
        byte[] bytes = reader.ReadBytes(length);
        string path = Encoding.ASCII.GetString(bytes);
        if (bytes.Length != length || !SafePath(path)) throw new InvalidDataException("Invalid application path.");
        return path;
    }
}
