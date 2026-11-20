// Table tests for pickLanding (Sources/landing.swift). Run with `make test`.
import CoreGraphics
import Foundation

struct Case {
  let name: String
  let origin: CGPoint
  let dir: CGVector
  let goal: CGPoint
  let pts: [CGPoint]
  let want: CGPoint?
}

let o = CGPoint.zero
let right = CGVector(dx: 100, dy: 0)
let cases: [Case] = [
  Case(name: "empty", origin: o, dir: right, goal: CGPoint(x: 100, y: 0), pts: [], want: nil),
  Case(name: "cone edge inside", origin: o, dir: right, goal: CGPoint(x: 100, y: 0),
       pts: [CGPoint(x: 100, y: 110)], want: CGPoint(x: 100, y: 110)),   // cos ~0.67
  Case(name: "cone edge outside", origin: o, dir: right, goal: CGPoint(x: 100, y: 0),
       pts: [CGPoint(x: 100, y: 130)], want: nil),                        // cos ~0.61
  Case(name: "within 4 px", origin: o, dir: right, goal: CGPoint(x: 100, y: 0),
       pts: [CGPoint(x: 4, y: 0)], want: nil),
  Case(name: "just past 4 px", origin: o, dir: right, goal: CGPoint(x: 100, y: 0),
       pts: [CGPoint(x: 4.5, y: 0)], want: CGPoint(x: 4.5, y: 0)),
  Case(name: "behind", origin: o, dir: right, goal: CGPoint(x: 100, y: 0),
       pts: [CGPoint(x: -50, y: 0)], want: nil),
  Case(name: "nearest to goal", origin: o, dir: right, goal: CGPoint(x: 100, y: 0),
       pts: [CGPoint(x: 20, y: 0), CGPoint(x: 90, y: 5), CGPoint(x: 200, y: 0)], want: CGPoint(x: 90, y: 5)),
  Case(name: "tie keeps first", origin: o, dir: right, goal: CGPoint(x: 100, y: 0),
       pts: [CGPoint(x: 100, y: 10), CGPoint(x: 100, y: -10)], want: CGPoint(x: 100, y: 10)),
]

var failed = 0
for c in cases {
  let got = pickLanding(from: c.origin, dir: c.dir, goal: c.goal, among: c.pts)
  if got != c.want {
    failed += 1
    print("FAIL \(c.name): got \(String(describing: got)), want \(String(describing: c.want))")
  }
}
print("\(cases.count - failed)/\(cases.count) passed")
exit(failed == 0 ? 0 : 1)
