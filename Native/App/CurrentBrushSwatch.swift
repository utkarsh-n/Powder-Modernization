import SwiftUI
import PowderEngine

extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 255) / 255,
                  green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}

/// Keep the engine's hue, lifting dark pigments in dark mode and shading pale ones in light mode.
/// Monochrome rendering prevents a symbol's built-in palette from overriding its material color.
struct MaterialSymbol: View {
    let symbol: String
    let color: UInt32
    var size: CGFloat = 18
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(Color(rgb: MaterialSymbolTint.rgb(color, dark: colorScheme == .dark,
                                                             increasedContrast: contrast == .increased)))
            .frame(width: size + 4, height: size + 4)
            .accessibilityHidden(true)
    }
}

struct CurrentBrushSwatch: View {
    let session: PlaygroundSession
    let size: CGFloat
    var body: some View {
        MaterialSymbol(symbol: session.selectedWall?.paletteSymbol ?? session.selectedMaterial.paletteSymbol,
                       color: session.currentBrushColor, size: size)
    }
}
