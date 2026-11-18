// The landing for a pad key, shared by windows-snap.cs and tests/landing-test.cs.
// Mirrors pickLanding in Sources/shared/Landing.swift; tests/landing-cases.txt keeps the two in step.
using System;
using System.Collections.Generic;
using System.Drawing;

static class PadLanding
{
    // Among candidates within ~50 degrees of the offset (cosine > 0.64) and more than 4 px from
    // the origin, the one closest to origin + offset. Earlier candidates win ties.
    public static Point? Pick(IEnumerable<Point> candidates, Point origin, double ox, double oy)
    {
        double length = Math.Sqrt(ox * ox + oy * oy), gx = origin.X + ox, gy = origin.Y + oy, best = double.MaxValue;
        Point? nearest = null;
        foreach (var p in candidates)
        {
            double vx = p.X - origin.X, vy = p.Y - origin.Y, distance = Math.Sqrt(vx * vx + vy * vy);
            if (distance <= 4 || (vx * ox + vy * oy) / (distance * length) <= 0.64) continue;
            double toGoal = (p.X - gx) * (p.X - gx) + (p.Y - gy) * (p.Y - gy);
            if (toGoal < best)
            {
                best = toGoal;
                nearest = p;
            }
        }
        return nearest;
    }
}
