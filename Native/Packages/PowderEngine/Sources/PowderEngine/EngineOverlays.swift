import Foundation
import CBridge

public struct EngineWallType: Identifiable, Hashable, Sendable {
    public let id: Int32
    public let name: String
    public let identifier: String
    public let summary: String
    public let colorRGB: UInt32
    public let poweredColorRGB: UInt32
    public let drawStyle: Int

    public static let all: [EngineWallType] = (0..<tpt_wall_type_count()).compactMap { index in
        var value = TPTWallInfo()
        guard tpt_wall_type_info(index, &value) != 0 else { return nil }
        return EngineWallType(id: value.id, name: String(cString: value.name),
                              identifier: String(cString: value.identifier),
                              summary: String(cString: value.description), colorRGB: value.color_rgb,
                              poweredColorRGB: value.powered_color_rgb, drawStyle: Int(value.draw_style))
    }
    public static func named(_ identifier: String) -> EngineWallType? {
        all.first { $0.identifier == identifier || $0.name == identifier }
    }
}

public struct EngineWallCell: Identifiable, Hashable, Sendable {
    /// Stable pixel-space index of the top-left corner of this 4 × 4 wall cell.
    public var id: Int { y * 612 + x }
    public let x: Int
    public let y: Int
    public let type: EngineWallType
    /// Original electrical charge timer. A positive value marks a powered wall.
    public let power: Int
    public let fanVelocityX: Float
    public let fanVelocityY: Float
    public var isPowered: Bool { power > 0 }
    public static let size = Int(tpt_wall_cell_size())
}

public struct EngineSign: Identifiable, Hashable, Sendable {
    public enum Justification: Int32, CaseIterable, Sendable {
        case left = 0, center = 1, right = 2, noPointer = 3
    }
    public let id: Int
    public let x: Int
    public let y: Int
    public let justification: Justification
    public let boundsX: Int
    public let boundsY: Int
    public let boundsWidth: Int
    public let boundsHeight: Int
    /// Plain resolved label. Native views should render this verbatim with no link action.
    public let text: String
    public let textTruncated: Bool
}

extension EngineWorld {
    /// O(1) inspection of the wall block containing this particle-pixel coordinate.
    public func wall(x: Int, y: Int) -> EngineWallCell? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        var value = TPTWallCell()
        guard tpt_world_wall_at(handle, Int32(x), Int32(y), &value) == 1,
              let type = EngineWallType.all.first(where: { $0.id == value.type }) else { return nil }
        return EngineWallCell(x: Int(value.x), y: Int(value.y), type: type, power: Int(value.power),
                              fanVelocityX: value.fan_velocity_x, fanVelocityY: value.fan_velocity_y)
    }

    public func walls() -> [EngineWallCell] {
        let count = tpt_world_copy_walls(handle, nil, 0)
        guard count > 0 else { return [] }
        var buffer = [TPTWallCell](repeating: TPTWallCell(), count: count)
        let written = buffer.withUnsafeMutableBufferPointer {
            tpt_world_copy_walls(handle, $0.baseAddress, $0.count)
        }
        return buffer.prefix(min(count, written)).compactMap { value in
            guard let type = EngineWallType.all.first(where: { $0.id == value.type }) else { return nil }
            return EngineWallCell(x: Int(value.x), y: Int(value.y), type: type, power: Int(value.power),
                                  fanVelocityX: value.fan_velocity_x, fanVelocityY: value.fan_velocity_y)
        }
    }

    public func signs() -> [EngineSign] {
        let count = tpt_world_copy_signs(handle, nil, 0)
        guard count > 0 else { return [] }
        var buffer = [TPTSign](repeating: TPTSign(), count: count)
        let written = buffer.withUnsafeMutableBufferPointer {
            tpt_world_copy_signs(handle, $0.baseAddress, $0.count)
        }
        return buffer.prefix(min(count, written)).map { value in
            let text = withUnsafeBytes(of: value.text) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
            return EngineSign(id: Int(value.index), x: Int(value.x), y: Int(value.y),
                              justification: .init(rawValue: value.justification) ?? .center,
                              boundsX: Int(value.bounds_x), boundsY: Int(value.bounds_y),
                              boundsWidth: Int(value.bounds_width), boundsHeight: Int(value.bounds_height),
                              text: text, textTruncated: value.text_truncated != 0)
        }
    }

    /// Sets one original wall block containing the given particle-pixel coordinate.
    public mutating func setWall(x: Int, y: Int, type: EngineWallType) throws {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        let handle = try prepareMutation()
        guard tpt_world_set_wall(handle, Int32(x), Int32(y), type.id) != 0 else {
            throw EngineError("Could not paint the wall.")
        }
    }

    /// Original OPS permits 1 to 45 printable ASCII characters per stored sign.
    @discardableResult
    public mutating func setSign(index: Int? = nil, text: String, x: Int, y: Int,
                                 justification: EngineSign.Justification = .center) throws -> Int {
        guard x >= 0, x < width, y >= 0, y < height,
              index == nil || (index! >= 0 && index! < 16) else {
            throw EngineError("The sign position or index is invalid.")
        }
        guard !text.isEmpty, text.utf8.count <= 45,
              text.utf8.allSatisfy({ $0 >= 32 && $0 <= 126 }) else {
            throw EngineError("Original OPS signs require 1 to 45 printable ASCII characters.")
        }
        let handle = try prepareMutation()
        let result = text.withCString {
            tpt_world_set_sign(handle, index.map(Int32.init) ?? -1, $0, Int32(x), Int32(y), justification.rawValue)
        }
        guard result >= 0 else { throw EngineError("Could not update the sign.") }
        return Int(result)
    }

    public mutating func removeSign(index: Int) throws {
        guard index >= 0, index < 16 else { throw EngineError("The sign index is invalid.") }
        let handle = try prepareMutation()
        guard tpt_world_remove_sign(handle, Int32(index)) != 0 else {
            throw EngineError("Could not remove the sign.")
        }
    }
}
