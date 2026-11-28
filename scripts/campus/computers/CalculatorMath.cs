#nullable enable
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using Complex = System.Numerics.Complex;
using Godot;
using Ast = Godot.Collections.Dictionary;

public partial class CalculatorMath : RefCounted
{
    private const int MaxDegree = 16;
    private const double Epsilon = 1e-10;

    public Ast Calculate(Ast tree, string operation, bool complex, string angles)
    {
        try
        {
            var expression = Read(tree, 0);
            if (!complex && (expression.Contains("i") || expression.HasOperator("∠")))
                throw new ArgumentException("Enable complex numbers for imaginary or polar input.");
            double angle = AngleScale(angles);
            if (operation is "auto" or "factor" || operation.StartsWith("isolate:", StringComparison.Ordinal))
                return RunSymbolic(expression, operation, complex, angle);
            if (operation == "convert")
            {
                if (!complex) throw new ArgumentException("Enable complex numbers to convert.");
                if (!IsComplexLiteral(expression))
                    throw new ArgumentException("Enter one complex number, such as 3 + 4i or 5∠30°.");
                operation = expression.HasOperator("∠") ? "rectangular" : "polar";
            }
            if (operation is "evaluate" or "polar" or "rectangular")
            {
                Complex value = expression.Evaluate(0, 0, AngleScale(angles), false);
                EnsureFinite(value);
                if (!complex && Math.Abs(value.Imaginary) > Epsilon)
                    throw new ArgumentException("Enable complex numbers for this result.");
                string text = operation == "polar"
                    ? $"{Format(value.Magnitude)} ∠ {Format(value.Phase)}"
                    : Print(value);
                return new Ast { ["text"] = text, ["real"] = value.Real, ["imaginary"] = value.Imaginary };
            }
            if (operation == "differentiate")
                return DifferentiateSymbolic(expression, angle);
            if (operation == "integrate")
                return IntegrateSymbolic(expression, angle);

            Complex[] polynomial = expression.Polynomial();
            if (operation is "expand" or "simplify")
                return Success(PrintPolynomial(polynomial));
            if (polynomial.Length == 1)
                return Success(polynomial[0].Magnitude < Epsilon ? "All x satisfy the equation." : "No solutions.");
            Complex[] roots = Roots(polynomial);
            string[] solutions = roots.Where(root => complex || Math.Abs(root.Imaginary) < 1e-6)
                .OrderBy(root => root.Real).ThenBy(root => root.Imaginary)
                .Select(root => Print(new Complex(root.Real, Math.Abs(root.Imaginary) < 1e-6 ? 0 : root.Imaginary)))
                .Distinct().ToArray();
            return Success(solutions.Length == 0 ? "No real solutions." : "x = " + string.Join(", ", solutions));
        }
        catch (ArgumentException error) { return new Ast { ["error"] = error.Message }; }
    }

    public Ast Measure(Ast tree, double start, double end, string angles, bool slope)
    {
        try
        {
            var node = Read(tree, 0);
            if (node.Operator == "=") node = node.Right!;
            double angle = AngleScale(angles);
            double result;
            if (slope)
            {
                var derivative = node.Derivative(angle);
                result = Real(derivative.Evaluate(start, 0, angle, true));
            }
            else
            {
                const int intervals = 1024;
                double step = (end - start) / intervals;
                result = Math.Abs(Real(node.Evaluate(start, 0, angle, true))) +
                         Math.Abs(Real(node.Evaluate(end, 0, angle, true)));
                for (int i = 1; i < intervals; i++)
                    result += (i % 2 == 0 ? 2 : 4) * Math.Abs(Real(node.Evaluate(start + i * step, 0, angle, true)));
                result *= Math.Abs(step) / 3;
            }
            if (!double.IsFinite(result)) throw new ArgumentException("Undefined on the selected range.");
            return Success((slope ? "Slope ≈ " : "Area ≈ ") + Format(result));
        }
        catch (ArgumentException error) { return new Ast { ["error"] = error.Message }; }
    }

    public Vector3[] Curve(Ast tree, int kind, string angles, double extent)
    {
        try
        {
            var node = Read(tree, 0);
            if (node.Operator == "=")
            {
                if (kind == 2 && node.Right is { Operator: "atom", Text: "z" })
                    node = node.Left!;
                else if (kind == 2 && node.Left is not { Operator: "atom", Text: "z" })
                    throw new ArgumentException("Write a 3D surface as z = f(x, y).");
                else node = node.Right!;
            }
            var points = new List<Vector3>();
            double scale = AngleScale(angles);
            if (kind == 2)
            {
                const int rows = 13;
                for (int axis = 0; axis < 2; axis++)
                {
                    for (int row = 0; row < rows; row++)
                    {
                        double lane = -extent + 2 * extent * row / (rows - 1);
                        for (int column = 0; column <= 24; column++)
                        {
                            double distance = -extent + 2 * extent * column / 24;
                            double x = axis == 0 ? distance : lane;
                            double y = axis == 0 ? lane : distance;
                            double z = PlotValue(node, x, y, scale);
                            points.Add(Math.Abs(z) <= 4 * extent ? new Vector3((float)x, (float)y, (float)z) : Break());
                        }
                        points.Add(Break());
                    }
                }
            }
            else
            {
                const int samples = 400;
                for (int index = 0; index <= samples; index++)
                {
                    double t = kind == 1 ? Math.Tau * index / samples : -extent + 2 * extent * index / samples;
                    double number = PlotValue(node, kind == 1 ? t / scale : t, 0, scale);
                    if (!(Math.Abs(number) <= 4 * extent)) points.Add(Break());
                    else if (kind == 1)
                        points.Add(new Vector3((float)(number * Math.Cos(t)), (float)(number * Math.Sin(t)), 0));
                    else points.Add(new Vector3((float)t, (float)number, 0));
                }
            }
            return points.ToArray();
        }
        catch (ArgumentException) { return Array.Empty<Vector3>(); }
    }

    private static Vector3 Break() => new(float.NaN, float.NaN, float.NaN);
    private static Ast Success(string text) => new() { ["text"] = text };
    private static double AngleScale(string mode) => mode == "deg" ? Math.PI / 180 : mode == "grad" ? Math.PI / 200 : 1.0;
    private static string Format(double value) => Math.Round(value, 8).ToString("G10", CultureInfo.InvariantCulture);
    private static string Print(Complex value)
    {
        if (Math.Abs(value.Imaginary) < 1e-8) return Format(value.Real);
        string imaginary = Math.Abs(Math.Abs(value.Imaginary) - 1) < 1e-8 ? "i" : Format(Math.Abs(value.Imaginary)) + "i";
        if (Math.Abs(value.Real) < 1e-8) return (value.Imaginary < 0 ? "-" : "") + imaginary;
        return Format(value.Real) + (value.Imaginary < 0 ? " - " : " + ") + imaginary;
    }
    private static double Real(Complex value)
    {
        EnsureFinite(value);
        if (Math.Abs(value.Imaginary) > 1e-7) throw new ArgumentException("The graph requires real values.");
        return value.Real;
    }
    private static void EnsureFinite(Complex value)
    {
        if (!double.IsFinite(value.Real) || !double.IsFinite(value.Imaginary)) throw new ArgumentException("Undefined result.");
    }
    private static double PlotValue(Node node, double x, double y, double angle)
    {
        try { return Real(node.Evaluate(x, y, angle, true)); }
        catch (ArgumentException) { return double.NaN; }
    }

    private static Node Read(Ast tree, int depth)
    {
        if (depth > 26 || !tree.ContainsKey("op")) throw new ArgumentException("Enter a valid equation.");
        string op = tree["op"].AsString();
        return op switch
        {
            "atom" => new Node("atom", tree["text"].AsString().ToLowerInvariant()),
            "group" => Read(tree["child"].AsGodotDictionary(), depth + 1),
            "prefix" => new Node("prefix", tree["sign"].AsString(), Read(tree["child"].AsGodotDictionary(), depth + 1)),
            "degree" => new Node("degree", "", Read(tree["child"].AsGodotDictionary(), depth + 1)),
            "function" => new Node("function", tree["name"].AsString(), Read(tree["child"].AsGodotDictionary(), depth + 1)),
            "+" or "-" or "*" or "/" or "^" or "ⁿ√" or "=" or "∠" => new Node(op, "", Read(tree["left"].AsGodotDictionary(), depth + 1), Read(tree["right"].AsGodotDictionary(), depth + 1)),
            _ => throw new ArgumentException("Unsupported operation.")
        };
    }

    private static Complex NthRoot(Complex radicand, Complex degree)
    {
        if (degree.Imaginary != 0 || !double.IsFinite(degree.Real) || degree.Real == 0)
            throw new ArgumentException("Enter a nonzero real root degree.");
        if (radicand == Complex.Zero)
        {
            if (degree.Real < 0) throw new ArgumentException("Zero has no negative-degree root.");
            return Complex.Zero;
        }
        double exponent = 1 / degree.Real;
        if (radicand.Imaginary == 0)
        {
            if (radicand.Real >= 0) return Math.Pow(radicand.Real, exponent);
            if (Math.Abs(degree.Real % 2) == 1) return -Math.Pow(-radicand.Real, exponent);
        }
        return Complex.Pow(radicand, exponent);
    }

    private static Complex[] Trim(Complex[] terms)
    {
        int length = terms.Length;
        while (length > 1 && terms[length - 1].Magnitude < Epsilon) length--;
        return terms[..length];
    }

    private static Complex[] Add(Complex[] a, Complex[] b, bool subtract)
    {
        var result = new Complex[Math.Max(a.Length, b.Length)];
        for (int i = 0; i < a.Length; i++) result[i] += a[i];
        for (int i = 0; i < b.Length; i++) result[i] += subtract ? -b[i] : b[i];
        return Trim(result);
    }

    private static Complex[] Multiply(Complex[] a, Complex[] b)
    {
        if (a.Length + b.Length > MaxDegree + 2) throw new ArgumentException($"Polynomial degree is limited to {MaxDegree}.");
        var result = new Complex[a.Length + b.Length - 1];
        for (int i = 0; i < a.Length; i++)
            for (int j = 0; j < b.Length; j++) result[i + j] += a[i] * b[j];
        return Trim(result);
    }

    private static string PrintPolynomial(Complex[] terms)
    {
        var result = new List<string>();
        for (int degree = terms.Length - 1; degree >= 0; degree--)
        {
            var coefficient = terms[degree];
            if (coefficient.Magnitude < Epsilon) continue;
            string variable = degree == 0 ? "" : degree == 1 ? "x" : $"x^{degree}";
            if (variable.Length == 0) result.Add(Print(coefficient));
            else if ((coefficient - Complex.One).Magnitude < Epsilon) result.Add(variable);
            else if ((coefficient + Complex.One).Magnitude < Epsilon) result.Add("-" + variable);
            else if (Math.Abs(coefficient.Imaginary) > Epsilon) result.Add($"({Print(coefficient)}){variable}");
            else result.Add(Print(coefficient) + variable);
        }
        return result.Count == 0 ? "0" : string.Join(" + ", result).Replace(" + -", " - ");
    }

    private static Complex[] Roots(Complex[] coefficients)
    {
        int degree = coefficients.Length - 1;
        if (degree == 1) return new[] { -coefficients[0] / coefficients[1] };
        if (degree == 2)
        {
            Complex square = Complex.Sqrt(coefficients[1] * coefficients[1] - 4 * coefficients[2] * coefficients[0]);
            return new[] { (-coefficients[1] - square) / (2 * coefficients[2]), (-coefficients[1] + square) / (2 * coefficients[2]) };
        }
        var terms = coefficients.Select(term => term / coefficients[^1]).ToArray();
        double radius = 1 + terms.Take(degree).Max(term => term.Magnitude);
        var roots = Enumerable.Range(0, degree).Select(i => Complex.FromPolarCoordinates(radius, Math.Tau * (i + .314) / degree)).ToArray();
        for (int pass = 0; pass < 800; pass++)
        {
            double movement = 0;
            for (int i = 0; i < degree; i++)
            {
                Complex value = terms[^1], denominator = Complex.One;
                for (int j = degree - 1; j >= 0; j--) value = value * roots[i] + terms[j];
                for (int j = 0; j < degree; j++)
                    if (i != j) denominator *= roots[i] - roots[j];
                if (denominator.Magnitude < 1e-26) continue;
                Complex adjustment = value / denominator;
                roots[i] -= adjustment;
                movement = Math.Max(movement, adjustment.Magnitude);
            }
            if (movement < 1e-10) break;
        }
        foreach (var root in roots)
        {
            EnsureFinite(root);
            Complex residual = terms[^1];
            for (int degreeIndex = degree - 1; degreeIndex >= 0; degreeIndex--)
                residual = residual * root + terms[degreeIndex];
            if (residual.Magnitude > 1e-5 * Math.Max(1, Math.Pow(root.Magnitude, degree)))
                throw new ArgumentException("The polynomial roots did not converge.");
        }
        return roots;
    }

    private sealed record Node(string Operator, string Text, Node? Left = null, Node? Right = null)
    {
        private static Node Number(double value) => new("atom", value.ToString("0.###############", CultureInfo.InvariantCulture));
        private static Node Op(string op, Node a, Node b) => new(op, "", a, b);
        private static Node Function(string name, Node child) => new("function", name, child);
        public bool Contains(string symbol) => Operator == "atom" && Text == symbol || Left?.Contains(symbol) == true || Right?.Contains(symbol) == true;
        public bool HasOperator(string op) => Operator == op || Left?.HasOperator(op) == true || Right?.HasOperator(op) == true;
        public string Display() => Operator switch
        {
            "atom" => Text, "prefix" => Text + "(" + Left!.Display() + ")",
            "function" => Text + "(" + Left!.Display() + ")",
            "degree" => "(" + Left!.Display() + ")°",
            _ => "(" + Left!.Display() + ")" + Operator + "(" + Right!.Display() + ")"
        };

        public Complex Evaluate(double x, double y, double angle, bool variables)
        {
            if (Operator == "atom")
            {
                if (double.TryParse(Text, NumberStyles.Float, CultureInfo.InvariantCulture, out double number)) return number;
                return Text switch
                {
                    "i" => Complex.ImaginaryOne, "pi" or "π" => Math.PI, "e" => Math.E,
                    "tau" or "τ" => Math.Tau, "phi" or "φ" => (1 + Math.Sqrt(5)) / 2,
                    "x" or "θ" when variables => x, "y" when variables => y,
                    _ => throw new ArgumentException($"Unknown value {Text}.")
                };
            }
            Complex left = Left!.Evaluate(x, y, angle, variables);
            if (Operator == "prefix") return Text == "-" ? -left : left;
            if (Operator == "degree") return left * Math.PI / 180;
            if (Operator == "function")
            {
                return Text switch
                {
                    "sin" => Complex.Sin(left * angle), "cos" => Complex.Cos(left * angle), "tan" => Complex.Tan(left * angle),
                    "asin" => Complex.Asin(left) / angle, "acos" => Complex.Acos(left) / angle, "atan" => Complex.Atan(left) / angle,
                    "sqrt" => Complex.Sqrt(left), "ln" => Complex.Log(left), "log" => Complex.Log10(left),
                    "exp" => Complex.Exp(left), "abs" => left.Magnitude, _ => throw new ArgumentException("Unsupported function.")
                };
            }
            Complex right = Right!.Evaluate(x, y, angle, variables);
            return Operator switch
            {
                "+" => left + right, "-" or "=" => left - right, "*" => left * right, "/" => left / right,
                "^" => left == Complex.Zero && right == Complex.Zero ? Complex.One : Complex.Pow(left, right),
                "ⁿ√" => NthRoot(left, right),
                "∠" => Polar(left, right),
                _ => throw new ArgumentException("Unsupported operation.")
            };
        }

        public Complex[] Polynomial()
        {
            if (!Contains("x"))
            {
                var constant = Evaluate(0, 0, 1, false);
                EnsureFinite(constant);
                return new[] { constant };
            }
            if (Operator == "atom" && Text == "x") return new[] { Complex.Zero, Complex.One };
            Complex[] left = Left!.Polynomial();
            if (Operator == "prefix") return Text == "-" ? left.Select(term => -term).ToArray() : left;
            if (Operator == "degree") return left.Select(term => term * Math.PI / 180).ToArray();
            if (Operator == "function") throw new ArgumentException("This operation requires a polynomial in x.");
            Complex[] right = Right!.Polynomial();
            if (Operator is "+" or "-" or "=") return Add(left, right, Operator != "+");
            if (Operator == "*") return Multiply(left, right);
            if (Operator == "/" && right.Length == 1 && right[0].Magnitude > Epsilon)
                return Trim(left.Select(term => term / right[0]).ToArray());
            if (Operator == "^" && right.Length == 1 && Math.Abs(right[0].Imaginary) < Epsilon)
            {
                double exponent = right[0].Real;
                if (exponent >= 0 && exponent <= MaxDegree && exponent == Math.Truncate(exponent))
                {
                    var power = new[] { Complex.One };
                    for (int i = 0; i < exponent; i++) power = Multiply(power, left);
                    return power;
                }
            }
            throw new ArgumentException("Use a polynomial in x with nonnegative integer powers and constant denominators.");
        }

        public Node Derivative(double angle)
        {
            try { return PolynomialDerivative(); }
            catch (ArgumentException) { }
            if (Operator == "atom") return Number(Text == "θ" ? 1 : 0);
            Node left = Left!, d = left.Derivative(angle);
            if (Operator == "prefix") return Text == "-" ? Op("*", Number(-1), d) : d;
            if (Operator == "degree") return Op("*", Number(Math.PI / 180), d);
            if (Operator == "function")
            {
                Node outer = Text switch
                {
                    "sin" => Op("*", Number(angle), Function("cos", left)),
                    "cos" => Op("*", Number(-angle), Function("sin", left)),
                    "tan" => Op("/", Number(angle), Op("^", Function("cos", left), Number(2))),
                    "exp" => this, "ln" => Op("/", Number(1), left),
                    "log" => Op("/", Number(1), Op("*", Number(Math.Log(10)), left)),
                    "sqrt" => Op("/", Number(.5), this),
                    _ => throw new ArgumentException("This derivative is unavailable.")
                };
                return Op("*", outer, d);
            }
            Node right = Right!, dr = right.Derivative(angle);
            return Operator switch
            {
                "+" or "-" => Op(Operator, d, dr),
                "*" => Op("+", Op("*", d, right), Op("*", left, dr)),
                "/" => Op("/", Op("-", Op("*", d, right), Op("*", left, dr)), Op("^", right, Number(2))),
                "^" => Op("*", this, Op("+", Op("*", dr, Function("ln", left)), Op("/", Op("*", right, d), left))),
                _ => throw new ArgumentException("This derivative is unavailable.")
            };
        }

        private Node PolynomialDerivative()
        {
            var terms = Polynomial();
            var variable = new Node("atom", "x");
            Node result = Number(0);
            for (int i = terms.Length - 1; i >= 1; i--)
            {
                Complex coefficient = terms[i] * i;
                if (coefficient.Magnitude < Epsilon) continue;
                Node value = Number(coefficient.Real);
                if (Math.Abs(coefficient.Imaginary) > Epsilon)
                    value = Op("+", value, Op("*", Number(coefficient.Imaginary), new Node("atom", "i")));
                Node term = i == 1 ? value : Op("*", value, i == 2 ? variable : Op("^", variable, Number(i - 1)));
                result = result == Number(0) ? term : Op("+", result, term);
            }
            return result;
        }

        public Node? Integral(double angle)
        {
            if (Operator is "+" or "-")
            {
                var a = Left!.Integral(angle);
                var b = Right!.Integral(angle);
                return a != null && b != null ? Op(Operator, a, b) : null;
            }
            if (Operator == "function" && Text is "sin" or "cos" or "exp")
            {
                var terms = Left!.Polynomial();
                if (terms.Length != 2 || Math.Abs(terms[1].Imaginary) > Epsilon) return null;
                double slope = terms[1].Real;
                return Text switch
                {
                    "sin" => Op("/", Function("cos", Left), Number(-slope * angle)),
                    "cos" => Op("/", Function("sin", Left), Number(slope * angle)),
                    _ => Op("/", this, Number(slope))
                };
            }
            if (Operator == "/" && Left == Number(1) && Right == new Node("atom", "x"))
                return Function("ln", Function("abs", Right));
            return null;
        }
    }
}
