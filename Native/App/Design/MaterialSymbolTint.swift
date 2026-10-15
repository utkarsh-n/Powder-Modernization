import Foundation

enum MaterialSymbolTint {
    /// Limit luminance without rotating hue. The simulation and its saved RGB values are unchanged.
    static func rgb(_ source: UInt32, dark: Bool, increasedContrast: Bool = false) -> UInt32 {
        let channels = [Double((source >> 16) & 255), Double((source >> 8) & 255), Double(source & 255)]
            .map { $0 / 255 }
        func luminance(_ values: [Double]) -> Double {
            let linear = values.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
        }
        let target = dark ? (increasedContrast ? 0.48 : 0.30) : (increasedContrast ? 0.10 : 0.18)
        let original = luminance(channels)
        guard dark ? original < target : original > target else { return source }
        // Mixing with white/black preserves the pigment's hue while adapting its lightness.
        let endpoint = dark ? 1.0 : 0.0
        var low = 0.0, high = 1.0
        for _ in 0..<16 {
            let mix = (low + high) / 2
            let value = luminance(channels.map { $0 + (endpoint - $0) * mix })
            if dark ? value < target : value > target { low = mix } else { high = mix }
        }
        let result = channels.map { UInt32((($0 + (endpoint - $0) * high) * 255).rounded()) }
        return result[0] << 16 | result[1] << 8 | result[2]
    }
}
