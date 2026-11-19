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
        public required int[][] LowerColumns;
        public required int[][] UpperColumns;
        public required int[] Permutation;
        public int[] ColumnOrder;
        public required ulong Hash;
    }

    private readonly List<Factor> _cache = new(4);

    public void Reset() => _cache.Clear();

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
            var (columnOrder, blockEnds) = FindIndependentBlocks(rows);
            var lu = new double[n][];
            var permutation = new int[n];
            int blockStart = 0;
            for (int i = 0; i < n; i++)
            {
                permutation[i] = columnOrder?[i] ?? i;
                if (columnOrder is null)
                {
                    lu[i] = (double[])rows[i].Clone();
                    continue;
                }
                var row = new double[n];
                for (int j = blockStart; j < blockEnds[i]; j++)
                    row[j] = rows[permutation[i]][columnOrder[j]];
                lu[i] = row;
                if (i+1 == blockEnds[i]) blockStart = i+1;
            }
            for (int k = 0; k < n; k++)
            {
                int end = blockEnds?[k] ?? n;
                int pivot = k;
                for (int j = k + 1; j < end; j++)
                    if (Math.Abs(lu[j][k]) > Math.Abs(lu[pivot][k])) pivot = j;
                if (Math.Abs(lu[pivot][k]) < 1e-14)
                    return new GodotDictionary { ["ok"] = false };
                (lu[k], lu[pivot]) = (lu[pivot], lu[k]);
                (permutation[k], permutation[pivot]) = (permutation[pivot], permutation[k]);
                for (int j = k + 1; j < end; j++)
                {
                    double factor = lu[j][k] / lu[k][k];
                    lu[j][k] = factor;
                    if (factor == 0.0) continue;
                    for (int column = k + 1; column < end; column++)
                        lu[j][column] -= factor * lu[k][column];
                }
            }
            var lowerColumns = new int[n][];
            var upperColumns = new int[n][];
            var columns = new List<int>(n);
            for (int i = 0; i < n; i++)
            {
                for (int j = 0; j < i; j++)
                    if (lu[i][j] != 0.0) columns.Add(j);
                lowerColumns[i] = columns.ToArray();
                columns.Clear();
                for (int j = i + 1; j < n; j++)
                    if (lu[i][j] != 0.0) columns.Add(j);
                upperColumns[i] = columns.ToArray();
                columns.Clear();
            }
            selected = new Factor {
                Matrix = rows, Lu = lu, Permutation = permutation, Hash = hash,
                LowerColumns = lowerColumns, UpperColumns = upperColumns,
                ColumnOrder = columnOrder
            };
            _cache.Insert(0, selected);
            if (_cache.Count > 4) _cache.RemoveAt(4);
        }

        return Solve(selected, rhs);
    }

    private static (int[] Order, int[] Ends) FindIndependentBlocks(double[][] matrix)
    {
        int n = matrix.Length;
        if (n < 24) return (null, null);
        var parent = new int[n];
        for (int i = 0; i < n; i++) parent[i] = i;
        int blockCount = n;
        for (int i = 0; i < n && blockCount > 1; i++)
        {
            for (int j = i + 1; j < n && blockCount > 1; j++)
            {
                // Include dependent-source and magnetic stamps in either direction.
                if (matrix[i][j] == 0.0 && matrix[j][i] == 0.0) continue;
                int a = Root(parent, i);
                int b = Root(parent, j);
                if (a == b) continue;
                parent[b] = a;
                blockCount--;
            }
        }
        if (blockCount == 1) return (null, null);
        var blocks = new Dictionary<int, List<int>>(blockCount);
        for (int i = 0; i < n; i++)
        {
            int root = Root(parent, i);
            if (!blocks.TryGetValue(root, out var block))
                blocks[root] = block = new List<int>();
            block.Add(i);
        }
        var order = new int[n];
        var ends = new int[n];
        int offset = 0;
        foreach (var block in blocks.Values)
        {
            block.CopyTo(order, offset);
            int end = offset + block.Count;
            Array.Fill(ends, end, offset, block.Count);
            offset = end;
        }
        return (order, ends);
    }

    private static int Root(int[] parent, int index)
    {
        while (parent[index] != index)
        {
            parent[index] = parent[parent[index]];
            index = parent[index];
        }
        return index;
    }

    public GodotDictionary SolveLast(double[] rhs)
    {
        if (_cache.Count == 0 || _cache[0].Permutation.Length != rhs.Length)
            return new GodotDictionary { ["ok"] = false };
        return Solve(_cache[0], rhs);
    }

    private static GodotDictionary Solve(Factor selected, double[] rhs)
    {
        int n = rhs.Length;

        var y = new double[n];
        var x = new double[n];
        for (int i = 0; i < n; i++)
        {
            double value = rhs[selected.Permutation[i]];
            foreach (int j in selected.LowerColumns[i]) value -= selected.Lu[i][j] * y[j];
            y[i] = value;
        }
        for (int i = n - 1; i >= 0; i--)
        {
            double value = y[i];
            foreach (int j in selected.UpperColumns[i]) value -= selected.Lu[i][j] * x[j];
            x[i] = value / selected.Lu[i][i];
            if (!double.IsFinite(x[i]) || Math.Abs(x[i]) > 1e9)
                return new GodotDictionary { ["ok"] = false };
        }
        if (selected.ColumnOrder is null)
            return new GodotDictionary { ["ok"] = true, ["x"] = x };
        for (int i = 0; i < n; i++) y[selected.ColumnOrder[i]] = x[i];
        return new GodotDictionary { ["ok"] = true, ["x"] = y };
    }
}
