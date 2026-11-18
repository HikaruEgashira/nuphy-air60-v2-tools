import Foundation

/// The landing for a pad key: among `candidates` lying within ~50 degrees of `offset`
/// (cosine > 0.64) and more than 4 px from `origin`, the one closest to `origin + offset`.
/// Earlier candidates win ties. Mirrored by `PadLanding.Pick` in Sources/windows-landing.cs;
/// tests/landing-cases.txt keeps the two in step.
func pickLanding(_ candidates: [CGPoint], from origin: CGPoint, offset: CGVector) -> CGPoint? {
  let goal = CGPoint(x: origin.x + offset.dx, y: origin.y + offset.dy)
  let len = hypot(offset.dx, offset.dy)
  return candidates.filter { p in
    let v = CGVector(dx: p.x - origin.x, dy: p.y - origin.y)
    let d = hypot(v.dx, v.dy)
    guard d > 4 else { return false }
    return (v.dx * offset.dx + v.dy * offset.dy) / (d * len) > 0.64
  }.min { hypot($0.x - goal.x, $0.y - goal.y) < hypot($1.x - goal.x, $1.y - goal.y) }
}
