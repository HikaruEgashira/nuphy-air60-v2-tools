// Table test for pickLanding: landing-test landing-cases.txt
import Foundation

func point(_ s: Substring) -> CGPoint {
  let n = s.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces))! }
  return CGPoint(x: n[0], y: n[1])
}

var failures = 0, cases = 0
for line in try! String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8).split(separator: "\n") {
  if line.hasPrefix("#") || line.allSatisfy(\.isWhitespace) { continue }
  let f = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
  let origin = point(Substring(f[1])), offset = point(Substring(f[2]))
  let candidates = f[3].split(separator: ";").map(point)
  let expected = f[4] == "none" ? nil : point(Substring(f[4]))
  let got = pickLanding(candidates, from: origin, offset: CGVector(dx: offset.x, dy: offset.y))
  cases += 1
  if got != expected { failures += 1; print("FAIL \(f[0]): got \(String(describing: got)), want \(f[4])") }
}
print("\(cases - failures)/\(cases) landing cases pass")
exit(failures == 0 && cases > 0 ? 0 : 1)
