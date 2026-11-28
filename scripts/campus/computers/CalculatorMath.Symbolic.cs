#nullable enable
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using Complex = System.Numerics.Complex;
using Ast = Godot.Collections.Dictionary;

public partial class CalculatorMath
{
    private static readonly string[] Variables = { "x", "y", "z" };

    private readonly record struct Powers(int X, int Y, int Z)
    {
        public int Total => X + Y + Z;
        public int Get(string variable) => variable == "x" ? X : variable == "y" ? Y : Z;
        public Powers Without(string variable) => new(variable == "x" ? 0 : X, variable == "y" ? 0 : Y, variable == "z" ? 0 : Z);
        public static Powers Of(string variable, int value) => variable switch
        {
            "x" => new(value, 0, 0), "y" => new(0, value, 0), _ => new(0, 0, value)
        };
        public static Powers operator +(Powers a, Powers b) => new(a.X+b.X, a.Y+b.Y, a.Z+b.Z);
        public static Powers operator -(Powers a, Powers b) => new(a.X-b.X, a.Y-b.Y, a.Z-b.Z);
    }

    private static Complex Polar(Complex magnitude, Complex angle)
    {
        if (Math.Abs(magnitude.Imaginary) > Epsilon || Math.Abs(angle.Imaginary) > Epsilon || magnitude.Real < 0)
            throw new ArgumentException("Enter a nonnegative magnitude and a real angle.");
        return Complex.FromPolarCoordinates(magnitude.Real, angle.Real);
    }

    private static bool IsComplexLiteral(Node node)
    {
        if (node.Operator == "∠")
            return !node.Left!.HasOperator("∠") && !node.Right!.HasOperator("∠") && !node.Contains("i");
        if (node.Operator is "+" or "-")
            return IsRealLiteral(node.Left!) && IsImaginaryTerm(node.Right!) ||
                   IsImaginaryTerm(node.Left!) && IsRealLiteral(node.Right!);
        return IsRealLiteral(node) || IsImaginaryTerm(node);
    }

    private static bool IsRealLiteral(Node node) => node.Operator == "atom" && node.Text != "i" ||
        node.Operator == "prefix" && IsRealLiteral(node.Left!);

    private static bool IsImaginaryTerm(Node node)
    {
        if (node.Operator == "prefix") return IsImaginaryTerm(node.Left!);
        if (node is { Operator: "atom", Text: "i" }) return true;
        return node.Operator == "*" && (IsRealLiteral(node.Left!) && node.Right is { Operator: "atom", Text: "i" } ||
            IsRealLiteral(node.Right!) && node.Left is { Operator: "atom", Text: "i" });
    }

    private static Ast RunSymbolic(Node expression, string operation, bool complex, double angle)
    {
        var variables = Variables.Where(expression.Contains).ToArray();
        if (expression.Operator != "=" && variables.Length == 0)
        {
            var numeric = expression.Evaluate(0,0,angle,false);
            EnsureFinite(numeric);
            if (!complex && Math.Abs(numeric.Imaginary)>Epsilon)
                throw new ArgumentException("Enable complex numbers for this result.");
            return new Ast { ["text"] = Print(numeric), ["real"] = numeric.Real, ["imaginary"] = numeric.Imaginary };
        }

        if (expression.Operator != "=")
        {
            if (operation == "auto" && expression.HasOperator("/") && ExactFraction(expression) is string fraction)
                return Success(fraction);
            if (!TryTerms(expression, angle, out var terms))
                return Success(Simplified(expression,angle).Display());
            return Success(operation == "factor" ? Factor(terms,variables) : PrintTerms(terms));
        }

        var difference = new Node("-", "", expression.Left, expression.Right);
        if (variables.Length == 0)
            return Success(difference.Evaluate(0,0,angle,false).Magnitude<Epsilon ? "True" : "False");
        if (!TryTerms(difference,angle,out var polynomial))
            return Success(Simplified(expression,angle).Display());

        string variable = operation.StartsWith("isolate:",StringComparison.Ordinal) ? operation[8..] : variables[0];
        if (!variables.Contains(variable)) variable = variables[0];
        int degree = polynomial.Keys.Select(power => power.Get(variable)).DefaultIfEmpty().Max();
        if (degree == 0)
            return Success(polynomial.Count == 0 ? $"All {variable} satisfy the equation." :
                variables.Length == 1 ? "No solutions." : PrintTerms(polynomial)+" = 0");
        if (variables.Length == 1)
        {
            try
            {
                var roots = Roots(Coefficients(polynomial,variable));
                var values = roots.Where(root => complex || Math.Abs(root.Imaginary)<1e-6)
                    .OrderBy(root => root.Real).ThenBy(root => root.Imaginary)
                    .Select(root => Print(new Complex(root.Real,Math.Abs(root.Imaginary)<1e-6 ? 0 : root.Imaginary)))
                    .Distinct().ToArray();
                if (values.Length == 0) return Success("No real solutions.");
                var result = Success(variable+" = "+string.Join(", ",values));
                if (values.Length == 1) result["answer"] = values[0];
                return result;
            }
            catch (ArgumentException) { return Success(PrintTerms(polynomial)+" = 0"); }
        }
        if (degree != 1) return Success(PrintTerms(polynomial)+" = 0");
        var coefficient = Slice(polynomial,variable,1);
        var remainder = Slice(polynomial,variable,0);
        if (coefficient.Count == 1 && coefficient.TryGetValue(default,out var constant))
            return Success(variable+" = "+PrintTerms(remainder.ToDictionary(term => term.Key,term => -term.Value/constant)));
        string numerator = PrintTerms(remainder.ToDictionary(term => term.Key,term => -term.Value));
        return Success(variable+" = ("+numerator+")/("+PrintTerms(coefficient)+")");
    }

    private static Dictionary<Powers,Complex> Slice(Dictionary<Powers,Complex> terms,string variable,int degree) =>
        terms.Where(term => term.Key.Get(variable)==degree).ToDictionary(term => term.Key.Without(variable),term => term.Value);

    private static Complex[] Coefficients(Dictionary<Powers,Complex> terms,string variable)
    {
        var coefficients = new Complex[terms.Keys.Select(power => power.Get(variable)).DefaultIfEmpty().Max()+1];
        foreach (var term in terms) coefficients[term.Key.Get(variable)] = term.Value;
        return coefficients;
    }

    private static bool TryTerms(Node node,double angle,out Dictionary<Powers,Complex> terms)
    {
        try { terms=Terms(node,angle); return true; }
        catch (ArgumentException) { terms=new(); return false; }
    }

    private static Dictionary<Powers,Complex> Terms(Node node,double angle)
    {
        if (node.Operator == "atom" && Variables.Contains(node.Text))
            return new() { [Powers.Of(node.Text,1)] = Complex.One };
        if (!Variables.Any(node.Contains))
        {
            var value=node.Evaluate(0,0,angle,false);
            EnsureFinite(value);
            var constant=new Dictionary<Powers,Complex>();
            Accumulate(constant,default,value);
            return constant;
        }
        if (node.Right == null && node.Operator is not ("degree" or "prefix"))
            throw new ArgumentException("Use a polynomial.");
        var left=Terms(node.Left!,angle);
        if (node.Operator is "degree" or "prefix")
        {
            double scale = node.Operator == "degree" ? Math.PI/180 : node.Text=="-" ? -1 : 1;
            return left.ToDictionary(term => term.Key,term => term.Value*scale);
        }
        var right=Terms(node.Right!,angle);
        switch (node.Operator)
        {
            case "+":
            case "-":
                foreach (var term in right) Accumulate(left,term.Key,term.Value*(node.Operator=="-" ? -1 : 1));
                return left;
            case "*": return Product(left,right);
            case "/" when right.Count == 1 && right.TryGetValue(default,out var denominator):
                return left.ToDictionary(term => term.Key,term => term.Value/denominator);
            case "^":
                var exponent = right.Count==0 ? Complex.Zero :
                    right.Count==1 && right.TryGetValue(default,out var value) ? value : Complex.ImaginaryOne;
                if (exponent.Imaginary != 0 || exponent.Real < 0 || exponent.Real > MaxDegree || exponent.Real!=Math.Truncate(exponent.Real)) break;
                var power=new Dictionary<Powers,Complex> { [default]=Complex.One };
                for (int index=0;index<exponent.Real;index++) power=Product(power,left);
                return power;
        }
        throw new ArgumentException("Use a polynomial within the supported degree.");
    }

    private static void Accumulate(Dictionary<Powers,Complex> terms,Powers power,Complex value)
    {
        value+=terms.GetValueOrDefault(power);
        EnsureFinite(value);
        if (power.Total>MaxDegree) throw new ArgumentException("Polynomial degree is too large.");
        if (value.Magnitude<Epsilon) terms.Remove(power);
        else terms[power]=value;
    }

    private static Dictionary<Powers,Complex> Product(Dictionary<Powers,Complex> left,Dictionary<Powers,Complex> right)
    {
        if ((long)left.Count*right.Count>16384) throw new ArgumentException("The expression is too large.");
        var result=new Dictionary<Powers,Complex>();
        foreach (var a in left)
            foreach (var b in right)
                Accumulate(result,a.Key+b.Key,a.Value*b.Value);
        if (result.Count>384) throw new ArgumentException("The expression is too large.");
        return result;
    }

    private static IEnumerable<KeyValuePair<Powers,Complex>> Ordered(Dictionary<Powers,Complex> terms) =>
        terms.OrderByDescending(term => term.Key.Total).ThenByDescending(term => term.Key.X).ThenByDescending(term => term.Key.Y);

    private static string Monomial(Powers power) => string.Join("",Variables.Select(variable =>
        power.Get(variable) switch { 0 => "", 1 => variable, var degree => $"{variable}^{degree}" }));

    private static string PrintTerms(Dictionary<Powers,Complex> terms)
    {
        string output="";
        foreach (var term in Ordered(terms))
        {
            bool real=Math.Abs(term.Value.Imaginary)<Epsilon;
            bool negative=real && term.Value.Real<0;
            var value=negative ? -term.Value : term.Value;
            string variables=Monomial(term.Key);
            string coefficient=variables.Length>0 && real && Math.Abs(value.Real-1)<Epsilon ? "" : Print(value);
            if (!real && variables.Length>0) coefficient="("+coefficient+")";
            if (!real && output.Length>0 && coefficient.StartsWith("-",StringComparison.Ordinal)) coefficient="("+coefficient+")";
            if (negative) output+=output.Length==0 ? "-" : " - ";
            else if (output.Length>0) output+=" + ";
            output+=coefficient+variables;
        }
        return output.Length==0 ? "0" : output;
    }

    private static Node NumberNode(double value) => new("atom",value.ToString("G15",CultureInfo.InvariantCulture));

    private static Node TermsNode(Dictionary<Powers,Complex> terms)
    {
        Node? sum=null;
        foreach (var term in Ordered(terms))
        {
            Node value=NumberNode(term.Value.Real);
            if (Math.Abs(term.Value.Imaginary)>Epsilon)
                value=new("+","",value,new Node("*","",NumberNode(term.Value.Imaginary),new Node("atom","i")));
            foreach (string variable in Variables)
            {
                int degree=term.Key.Get(variable);
                if (degree==0) continue;
                Node symbol=new("atom",variable);
                Node factor=degree==1 ? symbol : new Node("^","",symbol,NumberNode(degree));
                value=value is { Operator: "atom", Text: "1" } ? factor : new("*","",value,factor);
            }
            sum=sum==null ? value : new Node("+","",sum,value);
        }
        return sum ?? NumberNode(0);
    }

    private static Node Simplified(Node node,double angle)
    {
        if (node.Operator!="=" && TryTerms(node,angle,out var terms)) return TermsNode(terms);
        return node with { Left=node.Left==null ? null : Simplified(node.Left,angle),
            Right=node.Right==null ? null : Simplified(node.Right,angle) };
    }

    private static Ast DifferentiateSymbolic(Node node, double angle)
    {
        if (node.Operator == "=") throw new ArgumentException("Enter an expression to differentiate.");
        if (!TryTerms(node, angle, out var terms))
            return Success(Simplified(node.Derivative(angle), angle).Display());

        var variables = Variables.Where(node.Contains).ToArray();
        string variable = variables.Length == 1 ? variables[0] : "x";
        return Success(PrintTerms(terms.Where(term => term.Key.Get(variable) > 0)
            .ToDictionary(term => term.Key - Powers.Of(variable, 1),
                term => term.Value * term.Key.Get(variable))));
    }

    private static Ast IntegrateSymbolic(Node node,double angle)
    {
        if (node.Operator=="=") throw new ArgumentException("Enter an expression to integrate.");
        if (TryTerms(node,angle,out var terms))
        {
            if (terms.Count==0) return Success("0");
            var variables=Variables.Where(node.Contains).ToArray();
            string variable=variables.Length==1 ? variables[0] : "x";
            var parts=new List<string>();
            foreach (var term in Ordered(terms))
            {
                var power=term.Key+Powers.Of(variable,1);
                int degree=power.Get(variable);
                string numerator=PrintTerms(new() { [power]=term.Value });
                parts.Add(degree==1 ? numerator : $"{numerator}/{degree}");
            }
            return Success(string.Join(" + ",parts).Replace(" + -"," - "));
        }
        if (node.Integral(angle) is Node integral) return Success(Simplified(integral,angle).Display());
        throw new ArgumentException("A symbolic antiderivative is unavailable for this expression.");
    }

    private static string Factor(Dictionary<Powers,Complex> terms,string[] variables)
    {
        if (terms.Count<2) return PrintTerms(terms);
        var common=new Powers(terms.Keys.Min(power=>power.X),terms.Keys.Min(power=>power.Y),terms.Keys.Min(power=>power.Z));
        int divisor=0;
        foreach (var value in terms.Values)
        {
            if (Math.Abs(value.Imaginary)>Epsilon || Math.Abs(value.Real)>1e8 || value.Real!=Math.Truncate(value.Real))
            { divisor=1; break; }
            int number=(int)Math.Abs(value.Real);
            while (number!=0) (divisor,number)=(number,divisor%number);
        }
        divisor=Math.Max(divisor,1);
        string outside=(divisor>1 ? divisor.ToString(CultureInfo.InvariantCulture) : "")+Monomial(common);
        var remaining=terms.ToDictionary(term=>term.Key-common,term=>term.Value/divisor);
        if (variables.Length!=1) return outside.Length==0 ? PrintTerms(remaining) : outside+"*("+PrintTerms(remaining)+")";
        string variable=variables[0];
        var coefficients=Coefficients(remaining,variable);
        var factors=new List<string>();
        if (outside.Length>0) factors.Add(outside);
        while (coefficients.Length>2)
        {
            Complex[] candidates;
            try { candidates=Roots(coefficients); }
            catch (ArgumentException) { break; }
            bool extracted=false;
            foreach (var root in candidates.Where(root=>Math.Abs(root.Imaginary)<1e-6).OrderBy(root=>root.Real))
            {
                for (int denominator=1;denominator<=48;denominator++)
                {
                    double numerator=Math.Round(root.Real*denominator);
                    double value=numerator/denominator;
                    if (Math.Abs(value-root.Real)>1e-7) continue;
                    var quotient=new Complex[coefficients.Length-1];
                    quotient[^1]=coefficients[^1];
                    for (int i=quotient.Length-2;i>=0;i--) quotient[i]=coefficients[i+1]+value*quotient[i+1];
                    if ((coefficients[0]+value*quotient[0]).Magnitude>1e-7*Math.Max(1,coefficients[0].Magnitude)) continue;
                    factors.Add($"({variable}{(value<0 ? " + " : " - ")}{Math.Abs(numerator).ToString(CultureInfo.InvariantCulture)}{(denominator==1 ? "" : "/"+denominator)})");
                    coefficients=quotient;
                    extracted=true;
                    break;
                }
                if (extracted) break;
            }
            if (!extracted) break;
        }
        if (factors.Count==0) return PrintTerms(remaining);
        var rest=new Dictionary<Powers,Complex>();
        for (int i=0;i<coefficients.Length;i++) Accumulate(rest,Powers.Of(variable,i),coefficients[i]);
        factors.Add("("+PrintTerms(rest)+")");
        return string.Join("*",factors);
    }
}
