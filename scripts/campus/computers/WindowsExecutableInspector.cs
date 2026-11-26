using System;
using System.IO;
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

    private static Godot.Collections.Dictionary Failure(string message)
    {
        return new Godot.Collections.Dictionary { ["error"] = message };
    }
}
