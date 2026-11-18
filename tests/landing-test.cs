// Table test for PadLanding.Pick: landing-test.exe landing-cases.txt
// Build: csc.exe /nologo /r:System.Drawing.dll /out:landing-test.exe tests\landing-test.cs Sources\windows-landing.cs
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;

static class LandingTest
{
    static Point P(string s)
    {
        var n = s.Split(',').Select(x => int.Parse(x.Trim())).ToArray();
        return new Point(n[0], n[1]);
    }

    static int Main(string[] args)
    {
        int cases = 0, failures = 0;
        foreach (var line in File.ReadAllLines(args[0]))
        {
            if (line.StartsWith("#") || line.Trim().Length == 0) continue;
            var f = line.Split('|').Select(x => x.Trim()).ToArray();
            Point origin = P(f[1]), offset = P(f[2]);
            var candidates = f[3].Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries).Select(P).ToList();
            Point? expected = f[4] == "none" ? (Point?)null : P(f[4]);
            Point? got = PadLanding.Pick(candidates, origin, offset.X, offset.Y);
            cases++;
            if (got != expected)
            {
                failures++;
                Console.WriteLine("FAIL {0}: got {1}, want {2}", f[0], got.HasValue ? got.Value.ToString() : "none", f[4]);
            }
        }
        Console.WriteLine("{0}/{1} landing cases pass", cases - failures, cases);
        return failures == 0 && cases > 0 ? 0 : 1;
    }
}
