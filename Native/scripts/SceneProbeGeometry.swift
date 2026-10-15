import Foundation
import PowderCore

/// Probe-only geometry check. Large hollow circles can be represented by a closed
/// polyline; requiring a `.circle` primitive rejects valid compiled scenes.
struct ProbeCircularBoundary: Codable {
    let centerX: Double
    let centerY: Double
    let radius: Double
    let segmentCount: Int
    let maximumRadialError: Double
    let maximumJoinGap: Double

    static func glass(in plan: ScenePlan, width: Int, height: Int) -> Self? {
        let lines = plan.commands.filter { $0.material == "GLAS" && $0.shape == .line }
        if lines.count >= 8 {
            let starts = lines.map { CGPoint(x: $0.x1 * Double(width - 1), y: $0.y1 * Double(height - 1)) }
            let ends = lines.map { CGPoint(x: $0.x2 * Double(width - 1), y: $0.y2 * Double(height - 1)) }
            let centerX = starts.map(\.x).reduce(0, +) / Double(starts.count)
            let centerY = starts.map(\.y).reduce(0, +) / Double(starts.count)
            let radii = starts.map { hypot($0.x - centerX, $0.y - centerY) }
            let radius = radii.reduce(0, +) / Double(radii.count)
            let radialError = radii.map { abs($0 - radius) }.max() ?? .infinity
            let joinGap = ends.enumerated().map { index, end in
                let next = starts[(index + 1) % starts.count]
                return hypot(end.x - next.x, end.y - next.y)
            }.max() ?? .infinity
            let angles = starts.map { atan2($0.y - centerY, $0.x - centerX) }
            let sweep = angles.enumerated().reduce(0.0) { sum, pair in
                var delta = angles[(pair.offset + 1) % angles.count] - pair.element
                while delta > .pi { delta -= 2 * .pi }
                while delta < -.pi { delta += 2 * .pi }
                return sum + delta
            }
            guard radius > 4, radialError < 1.5, joinGap < 0.01,
                  abs(abs(sweep) - 2 * .pi) < 0.01 else { return nil }
            return Self(centerX: centerX, centerY: centerY, radius: radius, segmentCount: lines.count,
                        maximumRadialError: radialError, maximumJoinGap: joinGap)
        }
        guard let circle = plan.commands.first(where: { $0.material == "GLAS" && $0.shape == .circle }) else { return nil }
        return Self(centerX: circle.x1 * Double(width - 1), centerY: circle.y1 * Double(height - 1),
                    radius: circle.radius * Double(min(width, height)), segmentCount: 0,
                    maximumRadialError: 0, maximumJoinGap: 0)
    }
}
