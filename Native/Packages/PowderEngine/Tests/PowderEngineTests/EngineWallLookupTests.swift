import XCTest
import CBridge
@testable import PowderEngine

final class EngineWallLookupTests: XCTestCase {
    func testDirectLookupMatchesCatalogEnumerationAtEveryPixelInABlock() throws {
        var world = try EngineWorld()
        for (index, type) in EngineWallType.all.enumerated() where type.id != 0 {
            let x = 20 + index * 8, y = 80
            try world.setWall(x: x, y: y, type: type)
        }
        for wall in world.walls() {
            for dy in 0..<EngineWallCell.size {
                for dx in 0..<EngineWallCell.size {
                    XCTAssertEqual(world.wall(x: wall.x + dx, y: wall.y + dy), wall)
                }
            }
        }
        XCTAssertNil(world.wall(x: 600, y: 360))
    }

    func testLookupHandlesBoundsAndDoesNotMutateSnapshots() throws {
        var world = try EngineWorld()
        let wall = try XCTUnwrap(EngineWallType.named("DEFAULT_WL_WALL"))
        try world.setWall(x: 240, y: 160, type: wall)
        let snapshot = try world.renderSnapshot()
        XCTAssertNil(world.wall(x: Int.max, y: 160))
        XCTAssertNil(world.wall(x: 240, y: Int.min))
        XCTAssertEqual(tpt_world_wall_at(world.handle, 240, 160, nil), -1)
        var output = TPTWallCell()
        XCTAssertEqual(tpt_world_wall_at(world.handle, -1, 160, &output), -1)
        XCTAssertEqual(try world.renderSnapshot().packedCells, snapshot.packedCells)
    }
}
