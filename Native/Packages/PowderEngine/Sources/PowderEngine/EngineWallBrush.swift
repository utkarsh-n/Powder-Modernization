import Foundation
import CBridge

extension EngineWorld {
    @discardableResult
    public mutating func paintWallLine(fromX: Int, fromY: Int, toX: Int, toY: Int,
                                       radius: Int, wall: EngineWallType) throws -> Bool {
        guard (0..<width).contains(fromX), (0..<height).contains(fromY),
              (0..<width).contains(toX), (0..<height).contains(toY) else { return false }
        let radius = max(0, min(40, radius))
        var x = fromX, y = fromY
        let dx = abs(toX - fromX), dy = -abs(toY - fromY)
        let sx = fromX < toX ? 1 : -1, sy = fromY < toY ? 1 : -1
        var error = dx + dy
        var visited = Set<Int>()
        var changed = false
        while true {
            for py in max(0, y - radius)...min(height - 1, y + radius) {
                for px in max(0, x - radius)...min(width - 1, x + radius)
                    where (px - x) * (px - x) + (py - y) * (py - y) <= radius * radius {
                    let block = (py / 4) * (width / 4) + px / 4
                    if visited.insert(block).inserted {
                        let mayChange = tpt_world_wall_may_change(handle, Int32(px), Int32(py), wall.id)
                        guard mayChange >= 0 else { throw EngineError("Could not inspect the wall stroke.") }
                        if mayChange != 0 {
                            try setWall(x: px, y: py, type: wall)
                            changed = true
                        }
                    }
                }
            }
            if x == toX && y == toY { break }
            let twice = error * 2
            if twice >= dy { error += dy; x += sx }
            if twice <= dx { error += dx; y += sy }
        }
        return changed
    }
}
