import CoreGraphics

/// Picks the point within ~50 degrees of `dir` from `origin`, more than 4 px away, closest to
/// `goal`; the first point wins a tie.
func pickLanding(from origin: CGPoint, dir: CGVector, goal: CGPoint, among pts: [CGPoint]) -> CGPoint? {
  let len = hypot(dir.dx, dir.dy)
  return pts.filter { p in
    let v = CGVector(dx: p.x - origin.x, dy: p.y - origin.y)
    let d = hypot(v.dx, v.dy)
    guard d > 4 else { return false }
    return (v.dx * dir.dx + v.dy * dir.dy) / (d * len) > 0.64   // within ~50 degrees
  }.min { hypot($0.x - goal.x, $0.y - goal.y) < hypot($1.x - goal.x, $1.y - goal.y) }
}
