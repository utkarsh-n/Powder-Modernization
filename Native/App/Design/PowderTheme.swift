import SwiftUI
import AppKit

/// Interface colors follow the user's Mac appearance. Particle colors belong to the canvas.
enum PowderTheme {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let canvas = Color(nsColor: .underPageBackgroundColor)
    static let raised = Color(nsColor: .quaternaryLabelColor).opacity(0.12)
    static let border = Color(nsColor: .separatorColor)
    static let text = Color.primary
    static let secondary = Color.secondary
    static let accent = Color.accentColor
}
