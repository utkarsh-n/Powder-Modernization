import AppKit

@MainActor
final class PowderApplicationDelegate: NSObject, NSApplicationDelegate {
    static weak var session: PlaygroundSession?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let session = Self.session else { return .terminateNow }
        // Let the ordered worker finish pending edits and its atomic save before macOS exits.
        Task {
            do {
                try await session.saveBeforeClosing()
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                sender.reply(toApplicationShouldTerminate: false)
                NSAlert(error: error).runModal()
            }
        }
        return .terminateLater
    }
}
