using Godot;

[GlobalClass]
public partial class PaperStrokeCoverage : RefCounted
{
    public Godot.Collections.Dictionary Rasterize(Vector2[] points, Vector2 size, float width, float hardness)
    {
        var result = new Godot.Collections.Dictionary();
        if (points.Length == 0 || size.X <= 0 || size.Y <= 0)
            return result;

        float radius = Mathf.Max(0.5f, width * 0.5f);
        float feather = Mathf.Max(0.65f, radius * (1 - hardness));
        float outer = radius + 0.5f;
        var lower = points[0] * size;
        var upper = lower;
        foreach (var point in points)
        {
            lower = lower.Min(point * size);
            upper = upper.Max(point * size);
        }

        int left = Mathf.Max(0, Mathf.FloorToInt(lower.X - outer));
        int top = Mathf.Max(0, Mathf.FloorToInt(lower.Y - outer));
        int right = Mathf.Min(Mathf.CeilToInt(size.X), Mathf.CeilToInt(upper.X + outer));
        int bottom = Mathf.Min(Mathf.CeilToInt(size.Y), Mathf.CeilToInt(upper.Y + outer));
        int columns = right - left;
        int rows = bottom - top;
        if (columns <= 0 || rows <= 0)
            return result;

        var pixels = new byte[columns * rows * 4];
        var previous = points[0] * size;
        foreach (var point in points)
        {
            var end = point * size;
            var step = end - previous;
            float lengthSquared = step.LengthSquared();
            int endX = Mathf.Min(right, Mathf.CeilToInt(Mathf.Max(previous.X, end.X) + outer));
            int endY = Mathf.Min(bottom, Mathf.CeilToInt(Mathf.Max(previous.Y, end.Y) + outer));
            for (int y = Mathf.Max(top, Mathf.FloorToInt(Mathf.Min(previous.Y, end.Y) - outer)); y < endY; y++)
            {
                for (int x = Mathf.Max(left, Mathf.FloorToInt(Mathf.Min(previous.X, end.X) - outer)); x < endX; x++)
                {
                    var offset = new Vector2(x + 0.5f, y + 0.5f) - previous;
                    float fraction = lengthSquared > 0 ? Mathf.Clamp(offset.Dot(step) / lengthSquared, 0, 1) : 0;
                    float distance = (offset - step * fraction).Length();
                    float linear = Mathf.Clamp((outer - distance) / (feather + 0.5f), 0, 1);
                    byte alpha = (byte)Mathf.RoundToInt(255 * linear * linear * (3 - 2 * linear));
                    int index = ((y - top) * columns + x - left) * 4;
                    pixels[index] = pixels[index + 1] = pixels[index + 2] = 255;
                    if (alpha > pixels[index + 3])
                        pixels[index + 3] = alpha;
                }
            }
            previous = end;
        }

        // Bilinear samples outside segment bounds must also have white RGB.
        for (int index = 0; index < pixels.Length; index += 4)
            pixels[index] = pixels[index + 1] = pixels[index + 2] = 255;
        result["origin"] = new Vector2(left, top);
        result["texture"] = ImageTexture.CreateFromImage(Image.CreateFromData(columns, rows, false, Image.Format.Rgba8, pixels));
        return result;
    }
}
