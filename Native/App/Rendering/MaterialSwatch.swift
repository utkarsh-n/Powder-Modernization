import SwiftUI
import PowderEngine
import AppKit

/// These specimen images are exported through the same Metal pipeline used by the live canvas.
@MainActor
struct MaterialSwatch: View {
    let material: EngineElement
    var size: CGFloat = 30
    private static let specimens: [MaterialVisualFamily: Image] = Dictionary(uniqueKeysWithValues: MaterialVisualFamily.allCases.compactMap { family in
        guard let url = Bundle.main.url(forResource: family.assetName, withExtension: "png") else { return nil }
        guard let source = NSImage(contentsOf: url) else { return nil }
        return (family, Image(nsImage: source))
    })
    var body: some View {
        Self.specimens[material.visualProfile.family, default: Image(systemName: "circle.fill")]
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: size, height: size)
            .background(Color(red: 0.04, green: 0.055, blue: 0.075))
            .clipShape(RoundedRectangle(cornerRadius: max(5, size * 0.18)))
            .overlay(alignment: .bottomTrailing) {
                Circle().fill(Color(red: Double((material.colorRGB >> 16) & 255) / 255,
                                    green: Double((material.colorRGB >> 8) & 255) / 255,
                                    blue: Double(material.colorRGB & 255) / 255))
                    .frame(width: max(4, size * 0.12), height: max(4, size * 0.12))
                    .padding(size * 0.1)
            }
            .accessibilityHidden(true)
    }
}
