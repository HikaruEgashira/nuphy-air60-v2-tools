// Table tests for pickLanding (Sources/snap.swift). Built by `make test`.
import Foundation

let o = CGPoint(x: 100, y: 100)
let right = CGVector(dx: 100, dy: 0)
// cos(50.2 deg) ~= 0.640; 50 deg is inside the cone, 51 deg is outside.
func at(_ deg: Double, _ r: Double) -> CGPoint {
  CGPoint(x: 100 + r * cos(deg * .pi / 180), y: 100 + r * sin(deg * .pi / 180))
}

let cases: [(String, CGVector, [CGPoint], CGPoint?)] = [
  ("empty", right, [], nil),
  ("cone edge inside", right, [at(50, 50)], at(50, 50)),
  ("cone edge outside", right, [at(51, 50)], nil),
  ("4 px is too close", right, [CGPoint(x: 104, y: 100)], nil),
  ("just over 4 px", right, [CGPoint(x: 104.5, y: 100)], CGPoint(x: 104.5, y: 100)),
  ("behind", right, [CGPoint(x: 50, y: 100)], nil),
  ("nearest to goal", right, [CGPoint(x: 120, y: 100), CGPoint(x: 190, y: 110), CGPoint(x: 260, y: 100)], CGPoint(x: 190, y: 110)),
  ("tie keeps first", right, [CGPoint(x: 200, y: 110), CGPoint(x: 200, y: 90)], CGPoint(x: 200, y: 110)),
  ("zero direction", CGVector(dx: 0, dy: 0), [CGPoint(x: 150, y: 100)], nil),
]

var failed = 0
for (name, dir, pts, want) in cases {
  let got = pickLanding(from: o, dir: dir, among: pts)
  if got != want { failed += 1; print("FAIL \(name): got \(String(describing: got)), want \(String(describing: want))") }
  else { print("ok   \(name)") }
}
if failed > 0 { print("\(failed) failed"); exit(1) }
print("all \(cases.count) passed")
