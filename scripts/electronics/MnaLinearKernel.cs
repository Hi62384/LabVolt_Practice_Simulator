using System;
using System.Collections.Generic;
using Godot;
using GodotArray = Godot.Collections.Array;
using GodotDictionary = Godot.Collections.Dictionary;

namespace CollegeSimulator;

/// <summary>Double precision LU with a four-entry exact matrix cache for the circuit solver.</summary>
[GlobalClass]
public partial class MnaLinearKernel : RefCounted
{
    private sealed class Factor
    {
        public required double[][] Matrix;
        public required double[][] Lu;
        public required int[] Permutation;
        public required ulong Hash;
    }

    private readonly List<Factor> _cache = new(4);

    public void Reset() => _cache.Clear();

    public GodotDictionary Factorize(GodotArray matrix)
    {
        int n = matrix.Count;
        GodotDictionary probe = SolveCached(matrix, new double[n]);
        if (!(bool)probe["ok"]) return new GodotDictionary { ["ok"] = false };
        Factor factor = _cache[0];
        var lower = new GodotArray();
        var upper = new GodotArray();
        var diagonal = new double[n];
        for (int i = 0; i < n; i++)
        {
            var l = new GodotArray();
            var u = new GodotArray();
            for (int j = 0; j < i; j++)
                if (factor.Lu[i][j] != 0.0) l.Add(new GodotArray { j, factor.Lu[i][j] });
            for (int j = i + 1; j < n; j++)
                if (factor.Lu[i][j] != 0.0) u.Add(new GodotArray { j, factor.Lu[i][j] });
            lower.Add(l); upper.Add(u); diagonal[i] = factor.Lu[i][i];
        }
        return new GodotDictionary {
            ["ok"] = true, ["lower"] = lower, ["upper"] = upper,
            ["diagonal"] = diagonal, ["permutation"] = factor.Permutation
        };
    }

    public GodotDictionary SolveCached(GodotArray matrix, double[] rhs)
    {
        int n = rhs.Length;
        if (n == 0 || matrix.Count != n || n > 384)
            return new GodotDictionary { ["ok"] = false };

        var rows = new double[n][];
        ulong hash = 14695981039346656037UL;
        for (int i = 0; i < n; i++)
        {
            rows[i] = matrix[i].AsFloat64Array();
            if (rows[i].Length != n)
                return new GodotDictionary { ["ok"] = false };
            for (int j = 0; j < n; j++)
            {
                double value = rows[i][j];
                if (!double.IsFinite(value))
                    return new GodotDictionary { ["ok"] = false };
                hash = (hash ^ (ulong)BitConverter.DoubleToInt64Bits(value)) * 1099511628211UL;
            }
        }

        Factor selected = null;
        foreach (Factor entry in _cache)
        {
            if (entry.Hash != hash) continue;
            bool equal = true;
            for (int i = 0; i < n && equal; i++)
                for (int j = 0; j < n; j++)
                    if (BitConverter.DoubleToInt64Bits(entry.Matrix[i][j]) != BitConverter.DoubleToInt64Bits(rows[i][j]))
                    { equal = false; break; }
            if (equal) { selected = entry; break; }
        }

        if (selected is not null && _cache[0] != selected)
        {
            _cache.Remove(selected);
            _cache.Insert(0, selected);
        }

        if (selected is null)
        {
            var lu = new double[n][];
            var permutation = new int[n];
            for (int i = 0; i < n; i++)
            { lu[i] = (double[])rows[i].Clone(); permutation[i] = i; }
            for (int k = 0; k < n; k++)
            {
                int pivot = k;
                for (int j = k + 1; j < n; j++)
                    if (Math.Abs(lu[j][k]) > Math.Abs(lu[pivot][k])) pivot = j;
                if (Math.Abs(lu[pivot][k]) < 1e-14)
                    return new GodotDictionary { ["ok"] = false };
                (lu[k], lu[pivot]) = (lu[pivot], lu[k]);
                (permutation[k], permutation[pivot]) = (permutation[pivot], permutation[k]);
                for (int j = k + 1; j < n; j++)
                {
                    double factor = lu[j][k] / lu[k][k];
                    lu[j][k] = factor;
                    if (factor == 0.0) continue;
                    for (int column = k + 1; column < n; column++)
                        lu[j][column] -= factor * lu[k][column];
                }
            }
            selected = new Factor { Matrix = rows, Lu = lu, Permutation = permutation, Hash = hash };
            _cache.Insert(0, selected);
            if (_cache.Count > 4) _cache.RemoveAt(4);
        }

        var y = new double[n];
        var x = new double[n];
        for (int i = 0; i < n; i++)
        {
            double value = rhs[selected.Permutation[i]];
            for (int j = 0; j < i; j++) value -= selected.Lu[i][j] * y[j];
            y[i] = value;
        }
        for (int i = n - 1; i >= 0; i--)
        {
            double value = y[i];
            for (int j = i + 1; j < n; j++) value -= selected.Lu[i][j] * x[j];
            x[i] = value / selected.Lu[i][i];
            if (!double.IsFinite(x[i]) || Math.Abs(x[i]) > 1e9)
                return new GodotDictionary { ["ok"] = false };
        }
        return new GodotDictionary { ["ok"] = true, ["x"] = x };
    }
}
