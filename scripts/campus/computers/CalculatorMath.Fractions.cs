#nullable enable
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Numerics;

public partial class CalculatorMath
{
    private sealed record Fraction(Dictionary<Powers, BigInteger> Top, Dictionary<Powers, BigInteger> Bottom);
    private sealed class ZeroDenominatorException() : ArgumentException("Cannot divide by zero.");

    private static string? ExactFraction(Node expression)
    {
        try
        {
            Fraction fraction = ReadFraction(expression);
            BigInteger divisor = fraction.Top.Values.Concat(fraction.Bottom.Values)
                .Aggregate(BigInteger.Zero, BigInteger.GreatestCommonDivisor);
            if (Leading(fraction.Bottom).Sign < 0) divisor = -divisor;
            var top = fraction.Top.ToDictionary(term => term.Key, term => term.Value / divisor);
            var bottom = fraction.Bottom.ToDictionary(term => term.Key, term => term.Value / divisor);
            string numerator = PrintExactTerms(top);
            if (bottom.Count == 1 && bottom.GetValueOrDefault(default) == BigInteger.One) return numerator;
            string denominator = PrintExactTerms(bottom);
            // Group products as well as sums so implicit multiplication after '/' stays in the denominator.
            return $"({numerator})/({denominator})";
        }
        catch (ArgumentException error) when (error is not ZeroDenominatorException) { return null; }
    }

    private static Dictionary<Powers, BigInteger> ExactInteger(BigInteger value) =>
        value.IsZero ? new() : new() { [default] = value };

    private static Fraction ReadFraction(Node node)
    {
        if (node.Operator == "atom")
        {
            if (Variables.Contains(node.Text))
                return new(new() { [Powers.Of(node.Text, 1)] = BigInteger.One }, ExactInteger(1));
            var parts = node.Text.Split('e', 'E');
            int exponent = 0;
            if (parts.Length is 1 or 2
                && (parts.Length == 1 || int.TryParse(parts[1], NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out exponent))
                && BigInteger.TryParse(parts[0].Replace(".", ""), NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out var digits))
            {
                int dot = parts[0].IndexOf('.');
                long scale = (dot < 0 ? 0 : parts[0].Length - dot - 1L) - exponent;
                if (scale is >= -100 and <= 100 && digits.GetByteCount() <= 48)
                    return scale < 0
                        ? new(ExactInteger(digits * BigInteger.Pow(10, (int)-scale)), ExactInteger(1))
                        : new(ExactInteger(digits), ExactInteger(BigInteger.Pow(10, (int)scale)));
            }
            throw new ArgumentException("Expected a rational polynomial.");
        }

        if (node.Operator is not ("+" or "-" or "*" or "/" or "^" or "prefix"))
            throw new ArgumentException("Expected a rational polynomial.");
        Fraction left = ReadFraction(node.Left!);
        if (node.Operator == "prefix")
            return node.Text == "-" ? new(left.Top.ToDictionary(term => term.Key, term => -term.Value), left.Bottom) : left;
        Fraction right = ReadFraction(node.Right!);
        switch (node.Operator)
        {
            case "+":
            case "-":
                bool sameBottom = left.Bottom.Count == right.Bottom.Count &&
                    left.Bottom.All(term => right.Bottom.GetValueOrDefault(term.Key) == term.Value);
                var top = sameBottom ? new(left.Top) : ExactProduct(left.Top, right.Bottom);
                var addend = sameBottom ? right.Top : ExactProduct(right.Top, left.Bottom);
                foreach (var term in addend) AddExact(top, term.Key, node.Operator == "+" ? term.Value : -term.Value);
                return new(top, sameBottom ? left.Bottom : ExactProduct(left.Bottom, right.Bottom));
            case "*":
                return new(ExactProduct(left.Top, right.Top), ExactProduct(left.Bottom, right.Bottom));
            case "/":
                if (right.Top.Count == 0) throw new ZeroDenominatorException();
                if (right.Bottom.Keys.Any(power => power.Total > 0))
                    throw new ArgumentException("Keep restrictions from the original denominator.");
                return new(ExactProduct(left.Top, right.Bottom), ExactProduct(left.Bottom, right.Top));
            default:
                BigInteger divisor = right.Bottom.GetValueOrDefault(default);
                BigInteger dividend = right.Top.GetValueOrDefault(default);
                if (right.Top.Count > (dividend.IsZero ? 0 : 1) || right.Bottom.Count != 1 || divisor.IsZero
                    || dividend % divisor != 0 || dividend / divisor < 0 || dividend / divisor > MaxDegree)
                    throw new ArgumentException("Unsupported rational exponent.");
                if (dividend.IsZero && left.Bottom.Keys.Any(power => power.Total > 0))
                    throw new ArgumentException("Keep restrictions from the original denominator.");
                var power = new Fraction(ExactInteger(1), ExactInteger(1));
                for (int i = 0; i < (int)(dividend / divisor); i++)
                    power = new(ExactProduct(power.Top, left.Top), ExactProduct(power.Bottom, left.Bottom));
                return power;
        }
    }

    private static Dictionary<Powers, BigInteger> ExactProduct(Dictionary<Powers, BigInteger> a, Dictionary<Powers, BigInteger> b)
    {
        if ((long)a.Count * b.Count > 16384) throw new ArgumentException("The expression is too large.");
        var result = new Dictionary<Powers, BigInteger>();
        foreach (var left in a)
            foreach (var right in b)
                AddExact(result, left.Key + right.Key, left.Value * right.Value);
        return result;
    }

    private static void AddExact(Dictionary<Powers, BigInteger> terms, Powers power, BigInteger value)
    {
        value += terms.GetValueOrDefault(power);
        if (power.Total > MaxDegree || value.GetByteCount() > 48 || terms.Count > 384)
            throw new ArgumentException("The expression is too large.");
        if (value.IsZero) terms.Remove(power);
        else terms[power] = value;
    }

    private static IEnumerable<KeyValuePair<Powers, BigInteger>> OrderedExact(Dictionary<Powers, BigInteger> terms) =>
        terms.OrderByDescending(term => term.Key.Total).ThenByDescending(term => term.Key.X).ThenByDescending(term => term.Key.Y);

    private static BigInteger Leading(Dictionary<Powers, BigInteger> terms) => OrderedExact(terms).First().Value;

    private static string PrintExactTerms(Dictionary<Powers, BigInteger> terms)
    {
        var pieces = new List<string>();
        foreach (var term in OrderedExact(terms))
        {
            string variables = Monomial(term.Key);
            var magnitude = BigInteger.Abs(term.Value);
            string coefficient = magnitude.IsOne && variables.Length > 0 ? "" : magnitude.ToString(CultureInfo.InvariantCulture);
            string sign = term.Value.Sign < 0 ? (pieces.Count == 0 ? "-" : " - ") : (pieces.Count == 0 ? "" : " + ");
            pieces.Add(sign + coefficient + variables);
        }
        return pieces.Count == 0 ? "0" : string.Concat(pieces);
    }
}
