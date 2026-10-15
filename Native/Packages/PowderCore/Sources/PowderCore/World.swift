import Foundation

public enum WorldError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedVersion(Int)
    case invalidDimensions
    case invalidCellCount
    case invalidTemperature
    case invalidRandomState
    case invalidAirField
    case saveTooLarge

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "This scene uses unsupported save version \(version)."
        case .invalidDimensions: "Scene dimensions must be between 8 × 8 and 612 × 384."
        case .invalidCellCount: "The scene's particle grid is incomplete."
        case .invalidTemperature: "The scene contains an invalid temperature."
        case .invalidRandomState: "The scene contains an invalid random generator state."
        case .invalidAirField: "The scene contains an invalid air field."
        case .saveTooLarge: "The scene exceeds the 32 MB save limit."
        }
    }
}

/// A deterministic cellular sandbox. Coordinates have their origin at the top left.
/// Initial dimensions are clamped to 8...612 columns and 8...384 rows.
/// Reads outside the grid return stone; writes outside the grid do nothing.
public struct World: Sendable {
    public let width: Int
    public let height: Int
    public private(set) var cells: [Cell]
    public private(set) var tick: UInt64 = 0
    public private(set) var airCells: [AirCell]
    public var airWidth: Int { (width + 3) / 4 }
    public var airHeight: Int { (height + 3) / 4 }

    public static let supportedInteractionSummary = "Battery → touching wire/metal/salt water → pulsed charge and heat → fuse → explosives → blast pressure and particle displacement. Fire also ignites oil, wood, coal, plants, gas, and thermite. Water quenches fire/lava, germinates seeds, grows plants, and dissolves salt. Heat melts ice, boils water, condenses steam, melts metal and glass. This is a deterministic cellular sandbox with simplified pulse circuits and coarse air dynamics."

    private var randomState: UInt64
    private var initialSeed: UInt64
    private var processed: [Bool]
    private var heatDelta: [Float]
    private var electricalState: [UInt16]
    private var airBuffer: [AirCell]
    private static let fallbackSeed: UInt64 = 0x9E3779B97F4A7C15
    private static let maximumSaveBytes = 32 * 1_024 * 1_024

    public init(width: Int = 240, height: Int = 160, seed: UInt64 = 42) {
        self.width = min(612, max(8, width))
        self.height = min(384, max(8, height))
        let count = self.width * self.height
        cells = Array(repeating: Cell(), count: count)
        processed = Array(repeating: false, count: count)
        heatDelta = Array(repeating: 0, count: count)
        electricalState = Array(repeating: 0, count: count)
        let airCount = ((self.width + 3) / 4) * ((self.height + 3) / 4)
        airCells = Array(repeating: AirCell(), count: airCount)
        airBuffer = airCells
        randomState = seed == 0 ? Self.fallbackSeed : seed
        initialSeed = randomState
    }

    public subscript(x: Int, y: Int) -> Cell {
        get {
            guard contains(x, y) else { return Cell(material: .stone) }
            return cells[y * width + x]
        }
        set {
            guard contains(x, y) else { return }
            var cell = newValue
            cell.temperature = cell.temperature.isFinite ? min(5_000, max(-273.15, cell.temperature)) : 20
            cells[y * width + x] = cell
        }
    }

    public var particleCount: Int { cells.reduce(0) { $0 + ($1.material == .empty ? 0 : 1) } }

    public mutating func clear() {
        cells = Array(repeating: Cell(), count: width * height)
        airCells = Array(repeating: AirCell(), count: airWidth * airHeight)
        tick = 0
        randomState = initialSeed
    }

    /// Advances one fixed simulation tick. Call this from one serial owner.
    public mutating func step() {
        tick &+= 1
        for index in cells.indices {
            processed[index] = false
            heatDelta[index] = 0
        }
        exchangeHeat()
        propagateElectricity()
        advanceAir()

        // Alternate scan direction to avoid favoring the left side of a pile.
        // Movement stamps both positions so a particle moves at most once per tick.
        for y in stride(from: height - 1, through: 0, by: -1) {
            for column in 0..<width {
                let x = tick.isMultiple(of: 2) ? column : width - 1 - column
                let index = y * width + x
                guard !processed[index], cells[index].material != .empty else { continue }
                process(x: x, y: y, index: index)
            }
        }
    }

    /// Draws a continuous round brush stroke. Existing particles are preserved;
    /// use `erase` or `.empty` to remove them. Radius is bounded to 32 cells.
    public mutating func paintLine(
        fromX: Int, fromY: Int, toX: Int, toY: Int,
        radius: Int, material: Material, erase: Bool = false
    ) {
        let radius = min(32, max(0, radius))
        // Clipping endpoints also bounds work for accidental or malicious input.
        var x = min(width + radius, max(-radius - 1, fromX))
        var y = min(height + radius, max(-radius - 1, fromY))
        let endX = min(width + radius, max(-radius - 1, toX))
        let endY = min(height + radius, max(-radius - 1, toY))
        let dx = abs(endX - x)
        let dy = -abs(endY - y)
        let stepX = x < endX ? 1 : -1
        let stepY = y < endY ? 1 : -1
        var error = dx + dy
        while true {
            paintCircle(x: x, y: y, radius: radius, material: erase ? .empty : material)
            if x == endX && y == endY { break }
            let twiceError = 2 * error
            if twiceError >= dy { error += dy; x += stepX }
            if twiceError <= dx { error += dx; y += stepY }
        }
    }

    /// Replaces the scene with a contained sand-and-water experiment.
    public mutating func loadDemo() {
        clear()
        let left = width / 8
        let right = width * 7 / 8
        let floor = height * 7 / 8
        paintLine(fromX: left, fromY: height / 3, toX: left, toY: floor, radius: 1, material: .stone)
        paintLine(fromX: right, fromY: height / 3, toX: right, toY: floor, radius: 1, material: .stone)
        paintLine(fromX: left, fromY: floor, toX: right, toY: floor, radius: 1, material: .stone)
        for y in (height * 2 / 3)..<floor {
            paintLine(fromX: left + 2, fromY: y, toX: right - 2, toY: y, radius: 0, material: .water)
        }
        paintLine(fromX: width / 3, fromY: height / 5, toX: width / 2, toY: height / 3,
                  radius: max(1, width / 35), material: .sand)
        paintLine(fromX: width * 3 / 5, fromY: height / 2, toX: width * 3 / 4, toY: height / 2,
                  radius: 1, material: .wood)
        paintLine(fromX: width * 2 / 3, fromY: height / 3, toX: width * 3 / 4, toY: height / 3,
                  radius: max(1, width / 60), material: .oil)
    }

    public func encoded() throws -> Data {
        let save = Save(version: 2, width: width, height: height, cells: cells,
                        tick: tick, randomState: randomState, initialSeed: initialSeed, airCells: airCells)
        return try JSONEncoder().encode(save)
    }

    public static func decode(_ data: Data) throws -> World {
        guard data.count <= maximumSaveBytes else { throw WorldError.saveTooLarge }
        let save = try JSONDecoder().decode(Save.self, from: data)
        guard save.version == 1 || save.version == 2 else { throw WorldError.unsupportedVersion(save.version) }
        guard (8...612).contains(save.width), (8...384).contains(save.height) else {
            throw WorldError.invalidDimensions
        }
        guard save.cells.count == save.width * save.height else { throw WorldError.invalidCellCount }
        guard save.cells.allSatisfy({ $0.temperature.isFinite && (-273.15...5_000).contains($0.temperature) }) else {
            throw WorldError.invalidTemperature
        }
        guard save.randomState != 0, save.initialSeed != 0 else { throw WorldError.invalidRandomState }
        var world = World(width: save.width, height: save.height, seed: save.initialSeed)
        world.cells = save.cells
        world.tick = save.tick
        world.randomState = save.randomState
        if let air = save.airCells {
            guard air.count == world.airWidth * world.airHeight,
                  air.allSatisfy({ $0.pressure.isFinite && abs($0.pressure) <= 200
                      && $0.velocityX.isFinite && abs($0.velocityX) <= 30
                      && $0.velocityY.isFinite && abs($0.velocityY) <= 30 }) else {
                throw WorldError.invalidAirField
            }
            world.airCells = air
        }
        return world
    }

    private struct Save: Codable {
        let version: Int
        let width: Int
        let height: Int
        let cells: [Cell]
        let tick: UInt64
        let randomState: UInt64
        let initialSeed: UInt64
        let airCells: [AirCell]?
    }

    private func contains(_ x: Int, _ y: Int) -> Bool {
        x >= 0 && x < width && y >= 0 && y < height
    }

    private mutating func random(_ upperBound: Int) -> Int {
        randomState ^= randomState >> 12
        randomState ^= randomState << 25
        randomState ^= randomState >> 27
        return Int((randomState &* 0x2545F4914F6CDD1D) % UInt64(upperBound))
    }

    private mutating func paintCircle(x: Int, y: Int, radius: Int, material: Material) {
        let minX = max(0, x - radius)
        let maxX = min(width - 1, x + radius)
        let minY = max(0, y - radius)
        let maxY = min(height - 1, y + radius)
        guard minX <= maxX, minY <= maxY else { return }
        for py in minY...maxY {
            for px in minX...maxX where (px - x) * (px - x) + (py - y) * (py - y) <= radius * radius {
                let index = py * width + px
                if material == .empty {
                    cells[index] = Cell()
                } else if cells[index].material == .empty {
                    cells[index] = Cell(material: material, temperature: material.paintTemperature,
                                        lifetime: material.initialLifetime)
                }
            }
        }
    }

    private mutating func exchangeHeat() {
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                if x + 1 < width { transferHeat(index, index + 1) }
                if y + 1 < height { transferHeat(index, index + width) }
            }
        }
        for index in cells.indices {
            let material = cells[index].material
            let cooling: Float = material == .steam ? 0.015 : (material.isGas ? 0.01 : 0.002)
            let temperature = cells[index].temperature + heatDelta[index]
            cells[index].temperature = temperature + (20 - temperature) * cooling
        }
    }

    private mutating func transferHeat(_ a: Int, _ b: Int) {
        let first = cells[a]
        let second = cells[b]
        // Empty space conducts slowly. Equalized pairwise transfers are computed
        // before application, so heat diffusion has no scan-direction bias.
        let conductivity: Float = first.material == .empty || second.material == .empty ? 0.01 : 0.06
        let transfer = (second.temperature - first.temperature) * conductivity
        heatDelta[a] += transfer
        heatDelta[b] -= transfer
    }

    /// Samples the coarse air cell containing a fine-grid position.
    public func air(atX x: Int, y: Int) -> AirCell {
        guard contains(x, y) else { return AirCell() }
        return airCells[(y / 4) * airWidth + x / 4]
    }

    private mutating func propagateElectricity() {
        // Snapshot charge ages before writing any output. A pulse therefore
        // travels at most one connected conductor per tick in either direction.
        for index in cells.indices { electricalState[index] = cells[index].lifetime }
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                guard cells[index].material.isConductive else { continue }
                let age = electricalState[index]
                if age > 0 {
                    cells[index].lifetime = min(14, age) - 1
                } else {
                    for (dx, dy) in Self.neighbors {
                        guard contains(x + dx, y + dy) else { continue }
                        let other = (y + dy) * width + x + dx
                        let material = cells[other].material
                        if material == .battery || material == .spark
                            || (material.isConductive && electricalState[other] > 10) {
                            cells[index].lifetime = 14
                            break
                        }
                    }
                }
                if cells[index].isElectricallyActive {
                    let heating: Float = cells[index].material == .wire ? 24 : 12
                    cells[index].temperature = min(5_000, cells[index].temperature + heating)
                }
            }
        }
    }

    private mutating func advanceAir() {
        let columns = airWidth
        let rows = airHeight
        for y in 0..<rows {
            for x in 0..<columns {
                let index = y * columns + x
                let left = airCells[y * columns + max(0, x - 1)]
                let right = airCells[y * columns + min(columns - 1, x + 1)]
                let above = airCells[max(0, y - 1) * columns + x]
                let below = airCells[min(rows - 1, y + 1) * columns + x]
                let current = airCells[index]
                airBuffer[index].velocityX = x == 0 || x == columns - 1 ? 0
                    : max(-30, min(30, current.velocityX * 0.95 - (right.pressure - left.pressure) * 0.18))
                airBuffer[index].velocityY = y == 0 || y == rows - 1 ? 0
                    : max(-30, min(30, current.velocityY * 0.95 - (below.pressure - above.pressure) * 0.18))
            }
        }
        for y in 0..<rows {
            for x in 0..<columns {
                let index = y * columns + x
                let divergence = airBuffer[y * columns + min(columns - 1, x + 1)].velocityX
                    - airBuffer[y * columns + max(0, x - 1)].velocityX
                    + airBuffer[min(rows - 1, y + 1) * columns + x].velocityY
                    - airBuffer[max(0, y - 1) * columns + x].velocityY
                airBuffer[index].pressure = max(-200, min(200, (airCells[index].pressure - divergence * 0.32) * 0.96))
            }
        }
        swap(&airCells, &airBuffer)
    }

    private static let neighbors: [(Int, Int)] = [(0, 1), (-1, 0), (1, 0), (0, -1)]

    private mutating func process(x: Int, y: Int, index: Int) {
        react(x: x, y: y, index: index)
        guard !processed[index] else { return }
        let material = cells[index].material

        if material == .spark {
            if cells[index].lifetime == 0 { cells[index].lifetime = 3 }
            cells[index].lifetime -= 1
            if cells[index].lifetime == 0 { cells[index] = Cell() }
            processed[index] = true
            return
        }
        if material == .fuse && cells[index].lifetime > 0 {
            cells[index].temperature = 700
            cells[index].lifetime -= 1
            if cells[index].lifetime == 0 {
                cells[index] = Cell(material: .fire, temperature: 700, lifetime: 35)
            }
            processed[index] = true
            return
        }
        if material == .thermite && cells[index].lifetime > 0 {
            cells[index].temperature = 2_400
            for (dx, dy) in Self.neighbors where contains(x + dx, y + dy) {
                let neighbor = (y + dy) * width + x + dx
                cells[neighbor].temperature = min(5_000, cells[neighbor].temperature + 160)
            }
            cells[index].lifetime -= 1
            if cells[index].lifetime == 0 {
                cells[index] = Cell(material: .lava, temperature: 2_200)
            }
            processed[index] = true
            return
        }
        guard material != .empty, !material.isStationary else { processed[index] = true; return }

        if material == .fire {
            cells[index].temperature = max(650, cells[index].temperature)
            if cells[index].lifetime == 0 { cells[index].lifetime = 100 }
            cells[index].lifetime -= 1
            if cells[index].lifetime == 0 {
                cells[index] = Cell(material: .smoke, temperature: 120, lifetime: 160)
                processed[index] = true
                return
            }
        } else if material == .smoke {
            if cells[index].lifetime == 0 { cells[index].lifetime = 160 }
            cells[index].lifetime -= 1
            if cells[index].lifetime == 0 {
                cells[index] = Cell()
                processed[index] = true
                return
            }
        }

        // Air transport precedes gravity. Solids stay anchored; mobile particles
        // are moved without overwriting others, preserving their identity.
        let flow = air(atX: x, y: y)
        let threshold: Float = material.isGas ? 0.7 : 2.5
        if max(abs(flow.velocityX), abs(flow.velocityY)) > threshold {
            let dx = abs(flow.velocityX) > threshold ? (flow.velocityX > 0 ? 1 : -1) : 0
            let dy = abs(flow.velocityY) > threshold ? (flow.velocityY > 0 ? 1 : -1) : 0
            if push(index, toX: x + dx, toY: y + dy) { return }
        }

        let direction = random(2) == 0 ? -1 : 1
        if material.isGas {
            if move(index, x: x, y: y - 1, rising: true)
                || move(index, x: x + direction, y: y - 1, rising: true)
                || move(index, x: x - direction, y: y - 1, rising: true) { return }
            if random(3) == 0 {
                if move(index, x: x + direction, y: y, rising: true) { return }
                if move(index, x: x - direction, y: y, rising: true) { return }
            }
        } else {
            if move(index, x: x, y: y + 1)
                || move(index, x: x + direction, y: y + 1)
                || move(index, x: x - direction, y: y + 1) { return }
            if material.isLiquid && (material != .lava || random(3) == 0) {
                if move(index, x: x + direction, y: y, lateral: true) { return }
                if move(index, x: x - direction, y: y, lateral: true) { return }
            }
        }
        // A particle that stayed still can be displaced later in this scan.
    }

    private mutating func move(_ source: Int, x: Int, y: Int, rising: Bool = false, lateral: Bool = false) -> Bool {
        guard contains(x, y) else { return false }
        let destination = y * width + x
        guard !processed[destination] else { return false }
        let moving = cells[source].material
        let target = cells[destination].material
        guard !target.isStationary else { return false }
        let canDisplace: Bool
        if target == .empty {
            canDisplace = true
        } else if rising {
            canDisplace = target.isLiquid || (target.isGas && moving.density < target.density)
        } else if lateral {
            canDisplace = target.isGas
        } else {
            canDisplace = (target.isLiquid || target.isGas) && moving.density > target.density
        }
        guard canDisplace else { return false }
        cells.swapAt(source, destination)
        processed[source] = true
        processed[destination] = true
        return true
    }

    private mutating func push(_ source: Int, toX x: Int, toY y: Int) -> Bool {
        guard contains(x, y) else { return false }
        let destination = y * width + x
        guard cells[destination].material == .empty, !processed[destination] else { return false }
        cells.swapAt(source, destination)
        processed[source] = true
        processed[destination] = true
        return true
    }

    private mutating func ignite(_ index: Int) {
        let material = cells[index].material
        if material == .fuse && cells[index].lifetime == 0 {
            cells[index].lifetime = 12
            cells[index].temperature = max(700, cells[index].temperature)
        } else if material == .thermite && cells[index].lifetime == 0 {
            cells[index].lifetime = 45
            cells[index].temperature = 2_400
        } else if material.isExplosive {
            guard cells[index].temperature < (material == .gas ? 150 : 180) else { return }
            cells[index].temperature = 350
        } else if material == .wood || material == .oil || material == .plant || material == .seed || material == .coal {
            cells[index] = Cell(material: .fire, temperature: 650,
                                lifetime: material == .coal ? 300 : UInt16(100 + random(60)))
        } else { return }
        processed[index] = true
    }

    private func isIgnitionSource(_ index: Int) -> Bool {
        let cell = cells[index]
        return cell.material == .fire || cell.material == .lava || cell.material == .spark
            || cell.isElectricallyActive
            || (cell.material == .fuse && cell.lifetime > 0 && cell.lifetime <= 9)
            || (cell.material == .thermite && cell.lifetime > 0)
    }

    private mutating func react(x: Int, y: Int, index: Int) {
        let material = cells[index].material
        let temperature = cells[index].temperature
        let pressure = abs(air(atX: x, y: y).pressure)
        if material.isExplosive && temperature >= (material == .gas ? 150 : 180) {
            explode(x: x, y: y, material: material)
            return
        }
        switch material {
        case .ice where temperature > 0:
            cells[index] = Cell(material: .water, temperature: temperature)
        case .water where temperature >= 100:
            cells[index] = Cell(material: .steam, temperature: max(110, temperature))
        case .saltwater where temperature >= 105:
            // Preserve the salt while releasing vapor, only when vapor has room.
            for (dx, dy) in Self.neighbors where contains(x + dx, y + dy) {
                let other = (y + dy) * width + x + dx
                if cells[other].material == .empty {
                    cells[other] = Cell(material: .steam, temperature: max(110, temperature))
                    cells[index] = Cell(material: .salt, temperature: temperature)
                    processed[other] = true
                    break
                }
            }
        case .steam where temperature < 95:
            cells[index] = Cell(material: .water, temperature: max(20, temperature))
        case .lava where temperature < 650:
            cells[index] = Cell(material: .stone, temperature: temperature)
        case .wood where temperature >= 230, .oil where temperature >= 160,
             .plant where temperature >= 180, .seed where temperature >= 180,
             .coal where temperature >= 250:
            cells[index] = Cell(material: .fire, temperature: 650,
                                lifetime: material == .coal ? 300 : UInt16(100 + random(60)))
        case .fuse where temperature >= 150 && cells[index].lifetime == 0:
            cells[index].lifetime = 12
        case .thermite where temperature >= 500 && cells[index].lifetime == 0:
            cells[index].lifetime = 45
        case .metal where temperature >= 1_400, .wire where temperature >= 1_100,
             .glass where temperature >= 1_300, .stone where temperature >= 1_600,
             .brick where temperature >= 1_600, .sand where temperature >= 1_500:
            cells[index] = Cell(material: .lava, temperature: temperature)
        case .glass where pressure > 28, .brick where pressure > 60, .stone where pressure > 100:
            cells[index] = Cell(material: .sand, temperature: temperature)
        default: break
        }

        for (dx, dy) in Self.neighbors {
            let nx = x + dx
            let ny = y + dy
            guard contains(nx, ny) else { continue }
            let neighbor = ny * width + nx
            let current = cells[index].material
            let adjacent = cells[neighbor].material
            if (current.isWater && adjacent == .lava) || (current == .lava && adjacent.isWater) {
                let water = current.isWater ? index : neighbor
                let lava = current == .lava ? index : neighbor
                cells[water] = Cell(material: .steam, temperature: 150)
                cells[lava] = Cell(material: .stone, temperature: 500)
                processed[water] = true
                processed[lava] = true
                return
            }
            if (current.isWater && adjacent == .fire) || (current == .fire && adjacent.isWater) {
                let water = current.isWater ? index : neighbor
                let fire = current == .fire ? index : neighbor
                cells[water] = Cell(material: .steam, temperature: 110)
                cells[fire] = Cell(material: .smoke, temperature: 90, lifetime: 60)
                processed[water] = true
                processed[fire] = true
                return
            }
            if (current == .salt && adjacent == .water) || (current == .water && adjacent == .salt) {
                let water = current == .water ? index : neighbor
                let salt = current == .salt ? index : neighbor
                cells[water].material = .saltwater
                cells[water].lifetime = 0
                cells[salt] = Cell()
                processed[water] = true
                processed[salt] = true
                return
            }
            if (current == .seed && adjacent == .water) || (current == .water && adjacent == .seed) {
                let seed = current == .seed ? index : neighbor
                let water = current == .water ? index : neighbor
                cells[seed].material = .plant
                cells[water] = Cell()
                processed[seed] = true
                processed[water] = true
                return
            }
            if current == .plant && adjacent == .water && random(8) == 0 {
                cells[neighbor] = Cell(material: .plant, temperature: cells[neighbor].temperature)
                processed[neighbor] = true
            }
            if isIgnitionSource(index) && adjacent.isCombustible {
                cells[neighbor].temperature = min(5_000, cells[neighbor].temperature + 60)
                if adjacent == .wood || adjacent == .oil || adjacent == .coal || adjacent == .plant || adjacent == .seed {
                    if random(adjacent == .oil ? 3 : 6) == 0 { ignite(neighbor) }
                } else { ignite(neighbor) }
            }
            if current == .acid && [.wood, .sand, .stone, .metal, .wire, .brick, .plant, .seed, .coal].contains(adjacent) && random(4) == 0 {
                if cells[index].lifetime == 0 { cells[index].lifetime = 8 }
                cells[neighbor] = Cell()
                processed[neighbor] = true
                cells[index].lifetime -= 1
                if cells[index].lifetime == 0 {
                    cells[index] = Cell(material: .water, temperature: cells[index].temperature)
                    return
                }
            }
        }
    }

    private mutating func explode(x: Int, y: Int, material: Material) {
        let radius = material == .explosive ? 9 : (material == .gas ? 5 : 4)
        let strength: Float = material == .explosive ? 180 : (material == .gas ? 95 : 75)
        let origin = y * width + x
        cells[origin] = Cell(material: .fire, temperature: 1_200, lifetime: 45)
        processed[origin] = true
        let coarseX = x / 4
        let coarseY = y / 4
        for ay in max(0, coarseY - 2)...min(airHeight - 1, coarseY + 2) {
            for ax in max(0, coarseX - 2)...min(airWidth - 1, coarseX + 2) {
                let index = ay * airWidth + ax
                let dx = Float(ax - coarseX)
                let dy = Float(ay - coarseY)
                let falloff = 1 / (1 + dx * dx + dy * dy)
                airCells[index].pressure = min(200, airCells[index].pressure + strength * falloff)
                airCells[index].velocityX = max(-30, min(30, airCells[index].velocityX + dx * strength * 0.12 * falloff))
                airCells[index].velocityY = max(-30, min(30, airCells[index].velocityY + dy * strength * 0.12 * falloff))
            }
        }
        for py in max(0, y - radius)...min(height - 1, y + radius) {
            for px in max(0, x - radius)...min(width - 1, x + radius) {
                let dx = px - x
                let dy = py - y
                let distanceSquared = dx * dx + dy * dy
                guard distanceSquared > 0, distanceSquared <= radius * radius else { continue }
                let index = py * width + px
                let original = cells[index].material
                let distance = Float(distanceSquared).squareRoot()
                let force = strength * (1 - distance / Float(radius + 1))
                cells[index].temperature = min(5_000, cells[index].temperature + force * 5)
                if original.isExplosive {
                    // Chain charges on the following tick; never recursively
                    // explode or erase a neighboring charge in this loop.
                    cells[index].temperature = max(350, cells[index].temperature)
                    processed[index] = true
                    continue
                }
                if original == .glass || (original == .brick && force > 45) || (original == .stone && force > 90) {
                    cells[index].material = .sand
                } else if original.isCombustible {
                    ignite(index)
                } else if original.isWater && force > 25 {
                    cells[index] = Cell(material: .steam, temperature: max(150, cells[index].temperature))
                } else if original == .empty && distance < Float(radius) / 3 && random(5) == 0 {
                    cells[index] = Cell(material: .fire, temperature: 900, lifetime: 25)
                }
                if cells[index].material != .empty && !cells[index].material.isStationary {
                    let sx = dx == 0 ? 0 : (dx > 0 ? 1 : -1)
                    let sy = dy == 0 ? 0 : (dy > 0 ? 1 : -1)
                    _ = push(index, toX: px + sx, toY: py + sy)
                }
                processed[index] = true
            }
        }
    }
}
