import Foundation
import FoundationModels

@main struct IntelligenceProbe {
    static func main() async {
        if #available(macOS 26.0, *) {
            print("APPLE_INTELLIGENCE_AVAILABILITY=\(SystemLanguageModel.default.availability)")
        } else {
            print("APPLE_INTELLIGENCE_AVAILABILITY=requires macOS 26")
        }
    }
}
