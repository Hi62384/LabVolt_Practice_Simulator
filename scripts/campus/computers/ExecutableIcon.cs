using System;
using System.Buffers.Binary;
using System.IO;
using System.Reflection.PortableExecutable;
using Godot;

public partial class ExecutableIcon : RefCounted
{
    private const uint DirectoryFlag = 0x80000000;
    private const int IconType = 3;
    private const int GroupIconType = 14;
    private const int PreviewSize = 24;

    public byte[] ReadIcon(byte[] executable)
    {
        if (executable.Length < 64 || executable[0] != 'M' || executable[1] != 'Z')
            return Array.Empty<byte>();
        try
        {
            using var file = new MemoryStream(executable, writable: false);
            using var pe = new PEReader(file);
            var header = pe.PEHeaders.PEHeader;
            if (header == null || header.ResourceTableDirectory.Size < 16)
                return Array.Empty<byte>();
            var directory = header.ResourceTableDirectory;
            var section = pe.GetSectionData(directory.RelativeVirtualAddress);
            var table = section.GetContent(0, Math.Min(directory.Size, section.Length)).AsSpan();
            int icons = FindEntry(table, 0, IconType, true);
            if (icons < 0)
                return Array.Empty<byte>();

            int groups = FindEntry(table, 0, GroupIconType, true);
            int firstGroup = FindEntry(table, groups, -1, true);
            var group = ReadResource(pe, table, firstGroup);
            if (group.Length >= 6 && Read16(group, 2) == 1)
            {
                int count = Math.Min((int)Read16(group, 4), (group.Length - 6) / 14);
                int bestScore = int.MaxValue;
                byte[] best = Array.Empty<byte>();
                for (int i = 0; i < count; i++)
                {
                    int entry = 6 + i * 14;
                    int width = group[entry] == 0 ? 256 : group[entry];
                    int score = Math.Abs(width - PreviewSize) * 2 + (width < PreviewSize ? 64 : 0);
                    if (score >= bestScore)
                        continue;
                    int icon = FindEntry(table, icons, Read16(group, entry + 12), true);
                    var preview = Decode(ReadResource(pe, table, icon));
                    if (preview.Length == 0)
                        continue;
                    best = preview;
                    bestScore = score;
                }
                if (best.Length != 0)
                    return best;
            }
            return Decode(ReadResource(pe, table, FindEntry(table, icons, -1, true)));
        }
        catch (Exception error) when (error is BadImageFormatException or IOException
            or ArgumentException or InvalidOperationException or OverflowException)
        {
            return Array.Empty<byte>();
        }
    }

    private static int FindEntry(ReadOnlySpan<byte> table, int offset, int id, bool directory)
    {
        if (offset < 0 || offset > table.Length - 16)
            return -1;
        int count = Read16(table, offset + 12) + Read16(table, offset + 14);
        int start = offset + 16;
        if (count > (table.Length - start) / 8)
            return -1;
        for (int index = 0; index < count; index++)
        {
            int entry = start + index * 8;
            uint name = Read32(table, entry);
            uint target = Read32(table, entry + 4);
            if ((id < 0 || name == (uint)id) && ((target & DirectoryFlag) != 0) == directory)
                return (int)(target & ~DirectoryFlag);
        }
        return -1;
    }

    private static byte[] ReadResource(PEReader pe, ReadOnlySpan<byte> table, int directory)
    {
        int entry = FindEntry(table, directory, -1, false);
        if (entry < 0 || entry > table.Length - 16)
            return Array.Empty<byte>();
        uint rva = Read32(table, entry);
        uint size = Read32(table, entry + 4);
        if (rva > int.MaxValue || size == 0 || size > 1024 * 1024)
            return Array.Empty<byte>();
        var content = pe.GetSectionData((int)rva);
        return size <= content.Length ? content.GetContent(0, (int)size).AsSpan().ToArray() : Array.Empty<byte>();
    }

    private static byte[] Decode(byte[] icon)
    {
        using var image = new Image();
        if (icon.Length >= 24 && Read32(icon, 0) == 0x474e5089)
        {
            int width = BinaryPrimitives.ReadInt32BigEndian(icon.AsSpan(16));
            int height = BinaryPrimitives.ReadInt32BigEndian(icon.AsSpan(20));
            if (width is < 1 or > 256 || height is < 1 or > 256 || image.LoadPngFromBuffer(icon) != Error.Ok)
                return Array.Empty<byte>();
        }
        else
        {
            if (icon.Length < 40)
                return Array.Empty<byte>();
            int headerSize = (int)Read32(icon, 0);
            int width = (int)Read32(icon, 4);
            int height = (int)Read32(icon, 8) / 2;
            int bits = Read16(icon, 14);
            if (headerSize < 40 || headerSize > icon.Length || width is < 1 or > 256
                || height is < 1 or > 256 || bits is not (1 or 4 or 8 or 24 or 32) || Read32(icon, 16) != 0)
                return Array.Empty<byte>();

            int colors = 0;
            if (bits <= 8)
            {
                uint count = Read32(icon, 32);
                if (count > (1u << bits))
                    return Array.Empty<byte>();
                colors = count == 0 ? 1 << bits : (int)count;
            }
            int pixels = headerSize + colors * 4;
            int stride = (width * bits + 31) / 32 * 4;
            int mask = pixels + height * stride;
            int maskStride = (width + 31) / 32 * 4;
            if (mask > icon.Length)
                return Array.Empty<byte>();
            bool hasMask = maskStride * height <= icon.Length - mask;
            var rgba = new byte[width * height * 4];
            bool hasAlpha = false;
            for (int y = 0; y < height; y++)
            {
                for (int x = 0; x < width; x++)
                {
                    int source = pixels + (height - y - 1) * stride + x * bits / 8;
                    int target = (y * width + x) * 4;
                    if (colors > 0)
                    {
                        int index = bits == 8 ? icon[source] :
                            (icon[source] >> (8 - bits - (x * bits % 8))) & ((1 << bits) - 1);
                        if (index >= colors)
                            return Array.Empty<byte>();
                        source = headerSize + index * 4;
                    }
                    rgba[target] = icon[source + 2];
                    rgba[target + 1] = icon[source + 1];
                    rgba[target + 2] = icon[source];
                    rgba[target + 3] = bits == 32 ? icon[source + 3] : (byte)255;
                    hasAlpha |= bits == 32 && rgba[target + 3] != 0;
                }
            }
            if (!hasAlpha)
            {
                for (int y = 0; y < height; y++)
                {
                    for (int x = 0; x < width; x++)
                    {
                        bool masked = hasMask && (icon[mask + (height - y - 1) * maskStride + x / 8]
                            & (0x80 >> (x % 8))) != 0;
                        rgba[(y * width + x) * 4 + 3] = masked ? (byte)0 : (byte)255;
                    }
                }
            }
            image.SetData(width, height, false, Image.Format.Rgba8, rgba);
        }
        image.Resize(PreviewSize, PreviewSize, Image.Interpolation.Lanczos);
        return image.SavePngToBuffer();
    }

    private static ushort Read16(ReadOnlySpan<byte> data, int offset) =>
        BinaryPrimitives.ReadUInt16LittleEndian(data[offset..]);

    private static uint Read32(ReadOnlySpan<byte> data, int offset) =>
        BinaryPrimitives.ReadUInt32LittleEndian(data[offset..]);
}
