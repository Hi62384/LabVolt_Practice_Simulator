using System;
using System.Buffers.Binary;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using Godot;

[GlobalClass]
public partial class WorkspaceMesh : RefCounted
{
    private const int VertexLimit = 240_000;

    public ArrayMesh LoadMesh(string format, byte[] payload)
    {
        var vertices = format == "obj" ? ReadObj(payload) : ReadStl(payload);
        if (vertices == null || vertices.Count == 0 || vertices.Count % 3 != 0)
            return null;

        var surface = new SurfaceTool();
        surface.Begin(Mesh.PrimitiveType.Triangles);
        foreach (var vertex in vertices)
            surface.AddVertex(vertex);
        surface.GenerateNormals();
        var material = new StandardMaterial3D
        {
            AlbedoColor = new Color(0.20f, 0.68f, 0.80f),
            Roughness = 0.72f,
            CullMode = BaseMaterial3D.CullModeEnum.Disabled,
        };
        surface.SetMaterial(material);
        return surface.Commit();
    }

    private static List<Vector3> ReadObj(byte[] payload)
    {
        var positions = new List<Vector3>();
        var output = new List<Vector3>();
        using var reader = new StringReader(Encoding.UTF8.GetString(payload));
        while (reader.ReadLine() is string line)
        {
            line = line.Split('#', 2)[0].Trim();
            if (line.Length > 32768)
                return null;
            string[] fields = line.Split((char[])null, StringSplitOptions.RemoveEmptyEntries);
            if (fields.Length == 0)
                continue;
            if (fields[0] == "v")
            {
                if (positions.Count >= VertexLimit || !ReadTextVertex(fields, out Vector3 vertex))
                    return null;
                positions.Add(vertex);
            }
            else if (fields[0] == "f")
            {
                if (fields.Length < 4 || output.Count + 3 * (fields.Length - 3) > VertexLimit)
                    return null;
                var face = new Vector3[fields.Length - 1];
                for (int i = 1; i < fields.Length; i++)
                {
                    string indexField = fields[i].Split('/', 2)[0];
                    if (!int.TryParse(indexField, out int index))
                        return null;
                    index = index < 0 ? positions.Count + index : index - 1;
                    if (index < 0 || index >= positions.Count)
                        return null;
                    face[i - 1] = positions[index];
                }
                for (int i = 1; i < face.Length - 1; i++)
                {
                    output.Add(face[0]);
                    output.Add(face[i + 1]);
                    output.Add(face[i]);
                }
            }
        }
        return output;
    }

    private static List<Vector3> ReadStl(byte[] payload)
    {
        var vertices = new List<Vector3>();
        if (payload.Length >= 84)
        {
            uint triangles = BinaryPrimitives.ReadUInt32LittleEndian(payload.AsSpan(80, 4));
            if (triangles * 50L + 84 == payload.Length)
            {
                if (triangles > VertexLimit / 3)
                    return null;
                for (int i = 0; i < triangles; i++)
                {
                    int offset = 96 + i * 50;
                    for (int vertexIndex = 2; vertexIndex >= 0; vertexIndex--)
                    {
                        int at = offset + vertexIndex * 12;
                        var vertex = new Vector3(ReadFloat(payload, at), ReadFloat(payload, at + 4), ReadFloat(payload, at + 8));
                        if (!ValidVertex(vertex))
                            return null;
                        vertices.Add(vertex);
                    }
                }
                return vertices;
            }
        }
        using var reader = new StringReader(Encoding.UTF8.GetString(payload));
        while (reader.ReadLine() is string line)
        {
            line = line.Trim();
            if (!line.StartsWith("vertex", StringComparison.Ordinal))
                continue;
            if (line.Length > 128 || vertices.Count >= VertexLimit ||
                !ReadTextVertex(line.Split((char[])null, StringSplitOptions.RemoveEmptyEntries), out Vector3 vertex))
                return null;
            vertices.Add(vertex);
        }
        vertices.Reverse();
        return vertices;
    }

    private static float ReadFloat(byte[] data, int offset) =>
        BitConverter.Int32BitsToSingle(BinaryPrimitives.ReadInt32LittleEndian(data.AsSpan(offset, 4)));

    private static bool ReadTextVertex(string[] fields, out Vector3 vertex)
    {
        vertex = Vector3.Zero;
        if (fields.Length < 4 ||
            !float.TryParse(fields[1], NumberStyles.Float, CultureInfo.InvariantCulture, out float x) ||
            !float.TryParse(fields[2], NumberStyles.Float, CultureInfo.InvariantCulture, out float y) ||
            !float.TryParse(fields[3], NumberStyles.Float, CultureInfo.InvariantCulture, out float z))
            return false;
        vertex = new Vector3(x, y, z);
        return ValidVertex(vertex);
    }

    private static bool ValidVertex(Vector3 vertex) => vertex.IsFinite() && vertex.Abs().LengthSquared() < 1e16f;
}
