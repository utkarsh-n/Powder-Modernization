import AppKit
import Foundation
import PowderEngine

// Audit the production mappings against the real engine, not a duplicated list of element codes.
@main
struct VerifyMaterialSymbols {
    struct Entry: Codable {
        let code: String
        let name: String
        let kind: String
        let symbol: String
        let rgb: UInt32
        let darkRGB: UInt32
        let lightRGB: UInt32
    }

    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let missing = Set(EngineElement.allCases.map(\.identifier)).subtracting(MaterialSymbolCatalog.materials.keys)
        let stale = Set(MaterialSymbolCatalog.materials.keys).subtracting(EngineElement.allCases.map(\.identifier))
        guard missing.isEmpty && stale.isEmpty else {
            throw NSError(domain: "SymbolCoverage", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Missing materials: \(missing.sorted()); stale mappings: \(stale.sorted())"])
        }
        var entries = [Entry]()
        func add(_ code: String, _ name: String, _ kind: String, _ rgb: UInt32, _ symbol: String?) {
            guard let symbol else { fatalError("Missing explicit symbol: \(code)") }
            guard NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil else {
                fatalError("Unavailable symbol: \(code) = \(symbol)")
            }
            entries.append(Entry(code: code, name: name, kind: kind, symbol: symbol, rgb: rgb,
                                 darkRGB: MaterialSymbolTint.rgb(rgb, dark: true),
                                 lightRGB: MaterialSymbolTint.rgb(rgb, dark: false)))
        }
        for material in EngineElement.allCases.sorted(by: { $0.identifier < $1.identifier }) {
            add(material.identifier, material.name, "material", material.colorRGB,
                MaterialSymbolCatalog.materials[material.identifier])
        }
        for wall in EngineWallType.all {
            add(wall.identifier, wall.name, "wall", wall.colorRGB, MaterialSymbolCatalog.walls[wall.identifier])
        }
        precondition(Set(MaterialSymbolCatalog.materials.keys) == Set(EngineElement.allCases.map(\.identifier)), "Stale material mappings")
        precondition(Set(MaterialSymbolCatalog.walls.keys) == Set(EngineWallType.all.map(\.identifier)), "Stale wall mappings")
        for key in [\Entry.rgb, \Entry.darkRGB, \Entry.lightRGB] {
            let identities = entries.map { "\($0.symbol):\($0[keyPath: key])" }
            precondition(Set(identities).count == entries.count, "Duplicate symbol/color pair")
        }
        let metadataURL = URL(fileURLWithPath: "/Applications/SF Symbols.app/Contents/Resources/Metadata/name_availability.plist")
        let metadata = try PropertyListSerialization.propertyList(from: Data(contentsOf: metadataURL), format: nil) as! [String: Any]
        let symbols = metadata["symbols"] as! [String: String]
        let releases = metadata["year_to_release"] as! [String: [String: String]]
        for entry in entries {
            guard let year = symbols[entry.symbol], let version = releases[year]?["macOS"] else {
                fatalError("Missing Apple availability metadata: \(entry.symbol)")
            }
            precondition(version.compare("14.0", options: .numeric) != .orderedDescending,
                         "Symbol requires macOS \(version): \(entry.symbol)")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: output.appendingPathComponent("catalog.json"))
        for dark in [false, true] { try render(entries, dark: dark, output: output) }
        print("PASS: \(EngineElement.allCases.count - 1) materials + \(EngineWallType.all.count) walls + erase tool")
        print("PASS: \(Set(entries.map(\.symbol)).count) distinct SF Symbols; no repeated symbol/color pair in original, light or dark colors")
        print("PASS: Every symbol loads through AppKit and is available on macOS 14.0 according to Apple's installed metadata")
        print("PASS: Light/dark contact sheets and production catalog exported")
    }

    @MainActor static func render(_ entries: [Entry], dark: Bool, output: URL) throws {
        let columns = 7, cellWidth = 200, cellHeight = 56
        let width = columns * cellWidth, height = ((entries.count + columns - 1) / columns) * cellHeight + 60
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(calibratedWhite: dark ? 0.15 : 0.95, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        let foreground = NSColor(calibratedWhite: dark ? 0.92 : 0.1, alpha: 1)
        ("Powder · complete material and wall symbol catalog · \(dark ? "dark" : "light")" as NSString)
            .draw(at: NSPoint(x: 16, y: height - 36), withAttributes: [.font: NSFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: foreground])
        for (index, entry) in entries.enumerated() {
            let x = (index % columns) * cellWidth + 16
            let y = height - 60 - (index / columns + 1) * cellHeight
            let rgb = dark ? entry.darkRGB : entry.lightRGB
            let color = NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                                green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
            let symbol = NSImage(systemSymbolName: entry.symbol, accessibilityDescription: nil)!
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
                    .applying(.preferringMonochrome()))!
            let tinted = NSImage(size: symbol.size, flipped: false) { rect in
                symbol.draw(in: rect)
                color.setFill()
                rect.fill(using: .sourceIn)
                return true
            }
            let scale = min(26 / symbol.size.width, 26 / symbol.size.height)
            let size = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
            tinted.draw(in: NSRect(x: CGFloat(x) + (26 - size.width) / 2, y: CGFloat(y) + 14, width: size.width, height: size.height))
            (entry.code.replacingOccurrences(of: "DEFAULT_WL_", with: "WALL · ") as NSString)
                .draw(at: NSPoint(x: x + 36, y: y + 28), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold), .foregroundColor: foreground])
            (entry.symbol as NSString).draw(in: NSRect(x: x + 36, y: y + 2, width: 146, height: 26), withAttributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: foreground.withAlphaComponent(0.7)])
        }
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(dark ? "symbols-dark.png" : "symbols-light.png"))
    }
}
