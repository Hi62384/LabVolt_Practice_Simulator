using System;
using System.Collections.Generic;
using Godot;

public partial class EquipmentSurfaceGeometry : RefCounted
{
    public const int TextureSize = 256;
    private const int CellsPerAxis = 8;
    private readonly Dictionary<int, Surface> surfaces = new();

    private record Triangle(Vector3 A, Vector3 B, Vector3 C, Vector2 U, Vector2 V, Vector2 W);
    private readonly record struct Texel(int Index, Vector3 Position, Vector3 Normal);
    private record Surface(MeshInstance3D Node, Triangle[] Triangles, Aabb Bounds)
    {
        public List<Texel>[] Texels;
    }

    public void Register(int id, MeshInstance3D node)
    {
        var triangles = new List<Triangle>();
        var mesh = node.Mesh;
        for (int surface = 0; surface < mesh.GetSurfaceCount(); surface++)
        {
            var arrays = mesh.SurfaceGetArrays(surface);
            var vertices = arrays[(int)Mesh.ArrayType.Vertex].AsVector3Array();
            var uv = arrays[(int)Mesh.ArrayType.TexUV].AsVector2Array();
            var indices = arrays[(int)Mesh.ArrayType.Index].AsInt32Array();
            int count = indices.Length == 0 ? vertices.Length : indices.Length;
            for (int k = 0; k + 2 < count; k += 3)
            {
                int a = indices.Length == 0 ? k : indices[k];
                int b = indices.Length == 0 ? k + 1 : indices[k + 1];
                int c = indices.Length == 0 ? k + 2 : indices[k + 2];
                triangles.Add(new Triangle(vertices[a], vertices[b], vertices[c],
                    uv.Length > a ? uv[a] : Vector2.Zero,
                    uv.Length > b ? uv[b] : Vector2.Zero,
                    uv.Length > c ? uv[c] : Vector2.Zero));
            }
        }
        surfaces[id] = new Surface(node, triangles.ToArray(), mesh.GetAabb());
    }

    public void Clear() => surfaces.Clear();

    public Godot.Collections.Dictionary Pick(Vector3 origin, Vector3 direction)
    {
        float closest = float.PositiveInfinity;
        var result = new Godot.Collections.Dictionary();
        foreach (var (id, mesh) in surfaces)
        {
            if (!IsInstanceValid(mesh.Node) || !mesh.Node.IsVisibleInTree()) continue;
            var model = mesh.Node.GlobalTransform;
            var inverse = model.AffineInverse();
            var start = inverse * origin;
            var ray = inverse.Basis * direction;
            if (!mesh.Bounds.Grow(0.00001f).IntersectsSegment(start, start + ray * 20)) continue;
            foreach (var tri in mesh.Triangles)
            {
                if (!Intersect(start, ray, tri, out var point)) continue;
                var world = model * point;
                float distance = world.DistanceSquaredTo(origin);
                if (distance >= closest) continue;
                var normal = (tri.C - tri.A).Cross(tri.B - tri.A).Normalized();
                if (normal.Dot(ray) > 0) normal = -normal;
                closest = distance;
                result["id"] = id;
                result["local"] = point;
                result["local_normal"] = normal;
                result["point"] = world;
                result["normal"] = (inverse.Basis.Transposed() * normal).Normalized();
            }
        }
        return result;
    }

    public Image ProjectionDepth(Godot.Collections.Array<MeshInstance3D> meshes, Transform3D worldToProjector,
        Vector2 dimensions, float depth)
    {
        const int resolution = 96;
        var closest = new float[resolution * resolution];
        foreach (var node in meshes)
        {
            if (!IsInstanceValid(node) || !node.IsVisibleInTree()) continue;
            var relative = worldToProjector * node.GlobalTransform;
            var bounds = relative * node.GetAabb();
            var half = dimensions * 0.5f;
            if (bounds.Position.X > half.X || bounds.End.X < -half.X || bounds.Position.Y > half.Y ||
                bounds.End.Y < -half.Y || bounds.End.Z < -depth) continue;
            var mesh = node.Mesh;
            for (int surface = 0; surface < mesh.GetSurfaceCount(); surface++)
            {
                var arrays = mesh.SurfaceGetArrays(surface);
                var vertices = arrays[(int)Mesh.ArrayType.Vertex].AsVector3Array();
                var indices = arrays[(int)Mesh.ArrayType.Index].AsInt32Array();
                for (int i = 0; i < vertices.Length; i++)
                {
                    var point = relative * vertices[i];
                    vertices[i] = new Vector3((point.X / dimensions.X + .5f) * resolution,
                        (.5f - point.Y / dimensions.Y) * resolution, point.Z);
                }
                int count = indices.Length == 0 ? vertices.Length : indices.Length;
                for (int k = 0; k + 2 < count; k += 3)
                {
                    var a = vertices[indices.Length == 0 ? k : indices[k]];
                    var b = vertices[indices.Length == 0 ? k + 1 : indices[k]];
                    var c = vertices[indices.Length == 0 ? k + 2 : indices[k + 2]];
                    ProjectTriangle(closest, resolution, a, b, c, depth);
                }
            }
        }
        var bytes = new byte[closest.Length * sizeof(float)];
        Buffer.BlockCopy(closest, 0, bytes, 0, bytes.Length);
        return Image.CreateFromData(resolution, resolution, false, Image.Format.Rf, bytes);
    }

    private static void ProjectTriangle(float[] closest, int resolution, Vector3 a, Vector3 b, Vector3 c, float depth)
    {
        var start = new Vector2(a.X, a.Y);
        var edge1 = new Vector2(b.X, b.Y) - start;
        var edge2 = new Vector2(c.X, c.Y) - start;
        float area = edge1.Cross(edge2);
        if (Mathf.Abs(area) < 0.00001f) return;
        var lower = start.Min(start + edge1).Min(start + edge2);
        var upper = start.Max(start + edge1).Max(start + edge2);
        for (int y = Mathf.Max(0, Mathf.FloorToInt(lower.Y)); y < Mathf.Min(resolution, Mathf.CeilToInt(upper.Y)); y++)
        for (int x = Mathf.Max(0, Mathf.FloorToInt(lower.X)); x < Mathf.Min(resolution, Mathf.CeilToInt(upper.X)); x++)
        {
            var point = new Vector2(x + .5f, y + .5f) - start;
            float u = point.Cross(edge2) / area;
            float v = edge1.Cross(point) / area;
            if (u < 0 || v < 0 || u + v > 1) continue;
            var z = a.Z + (b.Z - a.Z) * u + (c.Z - a.Z) * v;
            int index = y * resolution + x;
            closest[index] = Mathf.Max(closest[index], Mathf.Clamp(z / (2 * depth) + .5f, 0, 1));
        }
    }

    private static bool Intersect(Vector3 start, Vector3 ray, Triangle tri, out Vector3 point)
    {
        point = default;
        var b = tri.B - tri.A;
        var c = tri.C - tri.A;
        var perpendicular = ray.Cross(c);
        float determinant = b.Dot(perpendicular);
        if (Mathf.Abs(determinant) < 1e-12f) return false;
        var offset = start - tri.A;
        float u = offset.Dot(perpendicular) / determinant;
        if (u < 0 || u > 1) return false;
        var q = offset.Cross(b);
        float v = ray.Dot(q) / determinant;
        if (v < 0 || u + v > 1) return false;
        float t = c.Dot(q) / determinant;
        if (t < 0) return false;
        point = start + ray * t;
        return true;
    }

    public byte[] PaintStroke(int id, byte[] rgba, Vector3[] positions, Vector3[] normals, float[] radii,
        Color color, float hardness, bool erase)
    {
        if (!surfaces.TryGetValue(id, out var mesh)) return Array.Empty<byte>();
        var transform = mesh.Node.GlobalTransform;
        var inverse = transform.AffineInverse();
        var count = Mathf.Min(positions.Length, Mathf.Min(normals.Length, radii.Length));
        bool changed = false;
        for (int i = 0; i < count; i++)
        {
            if (radii[i] <= 0) continue;
            changed |= Paint(mesh, ref rgba, transform, inverse, positions[i], normals[i], radii[i], color, hardness, erase);
        }
        return changed ? rgba : Array.Empty<byte>();
    }

    // Use the actual UV triangles to cover both sides of an atlas seam in one dab.
    private static bool Paint(Surface mesh, ref byte[] rgba, Transform3D transform, Transform3D inverse,
        Vector3 position, Vector3 normal, float radius, Color color, float hardness, bool erase)
    {
        var local = inverse * position;
        var localRadius = radius * Mathf.Max(inverse.Basis.X.Length(), Mathf.Max(inverse.Basis.Y.Length(), inverse.Basis.Z.Length()));
        if (!mesh.Bounds.Grow(localRadius).HasPoint(local)) return false;
        mesh.Texels ??= BuildTexels(mesh);
        var minimum = CellFor(mesh.Bounds, local - Vector3.One * localRadius);
        var maximum = CellFor(mesh.Bounds, local + Vector3.One * localRadius);
        var normalTransform = inverse.Basis.Transposed();
        bool changed = false;
        for (int z = minimum.Z; z <= maximum.Z; z++)
        for (int y = minimum.Y; y <= maximum.Y; y++)
        for (int x = minimum.X; x <= maximum.X; x++)
        {
            var bucket = mesh.Texels[CellIndex(x, y, z)];
            if (bucket == null) continue;
            foreach (var texel in bucket)
            {
                var delta = transform * texel.Position - position;
                float distance = delta.LengthSquared() / (radius * radius);
                if (distance >= 1) continue;
                var worldNormal = (normalTransform * texel.Normal).Normalized();
                if (worldNormal.Dot(normal) < -0.05f) continue;
                // Avoid bleeding to parallel surfaces hidden behind the point of contact.
                if (worldNormal.Dot(normal) > 0.95f && Mathf.Abs(delta.Dot(normal)) > radius * 0.2f) continue;
                float strength = hardness >= 0.999f ? color.A : color.A * (1 - Mathf.SmoothStep(hardness, 1, Mathf.Sqrt(distance)));
                if (strength < 1f / 255) continue;
                int index = texel.Index;
                float alpha = rgba.Length == 0 ? 0 : rgba[index + 3] / 255f;
                if (erase && alpha == 0) continue;
                if (rgba.Length == 0) rgba = new byte[TextureSize * TextureSize * 4];
                if (!erase)
                {
                    float mixed = alpha * (1 - strength);
                    float total = strength + mixed;
                    rgba[index] = Byte((color.R * strength + rgba[index] / 255f * mixed) / total);
                    rgba[index + 1] = Byte((color.G * strength + rgba[index + 1] / 255f * mixed) / total);
                    rgba[index + 2] = Byte((color.B * strength + rgba[index + 2] / 255f * mixed) / total);
                    rgba[index + 3] = Byte(total);
                }
                else rgba[index + 3] = Byte(alpha * (1 - strength));
                changed = true;
            }
        }
        return changed;
    }

    private static byte Byte(float value) => (byte)Mathf.Clamp(Mathf.RoundToInt(value * 255f), 0, 255);

    private static int CellIndex(int x, int y, int z) => (z * CellsPerAxis + y) * CellsPerAxis + x;

    private static Vector3I CellFor(Aabb bounds, Vector3 point)
    {
        var offset = (point - bounds.Position) * CellsPerAxis;
        var size = bounds.Size;
        return new Vector3I(Cell(offset.X, size.X), Cell(offset.Y, size.Y), Cell(offset.Z, size.Z));
    }

    private static int Cell(float offset, float extent) => extent > 0
        ? Mathf.Clamp(Mathf.FloorToInt(offset / extent), 0, CellsPerAxis - 1) : 0;

    private static List<Texel>[] BuildTexels(Surface mesh)
    {
        var cells = new List<Texel>[CellsPerAxis * CellsPerAxis * CellsPerAxis];
        foreach (var tri in mesh.Triangles)
        {
            var a = tri.U * TextureSize;
            var b = tri.V * TextureSize - a;
            var c = tri.W * TextureSize - a;
            float area = b.Cross(c);
            if (Mathf.Abs(area) < 0.00001f) continue;
            var lower = a.Min(a + b).Min(a + c);
            var upper = a.Max(a + b).Max(a + c);
            var normal = (tri.C - tri.A).Cross(tri.B - tri.A).Normalized();
            for (int y = Mathf.Max(0, Mathf.FloorToInt(lower.Y)); y < Mathf.Min(TextureSize, Mathf.CeilToInt(upper.Y)); y++)
            for (int x = Mathf.Max(0, Mathf.FloorToInt(lower.X)); x < Mathf.Min(TextureSize, Mathf.CeilToInt(upper.X)); x++)
            {
                var relative = new Vector2(x + 0.5f, y + 0.5f) - a;
                float u = relative.Cross(c) / area;
                float v = b.Cross(relative) / area;
                if (u < 0 || v < 0 || u + v > 1) continue;
                var point = tri.A + (tri.B - tri.A) * u + (tri.C - tri.A) * v;
                var cell = CellFor(mesh.Bounds, point);
                var index = CellIndex(cell.X, cell.Y, cell.Z);
                cells[index] ??= new List<Texel>();
                cells[index].Add(new Texel((y * TextureSize + x) * 4, point, normal));
            }
        }
        return cells;
    }
}
