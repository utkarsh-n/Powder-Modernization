#!/bin/zsh
set -euo pipefail

native_directory="${0:A:h:h}"
evidence_directory="${1:-${native_directory:h}/evidence/on-device-conversation-v6}"
engine_build="${2:-/private/tmp/powder-layout-engine-release}"
intelligence_build="${3:-/private/tmp/powder-conversation-tests}"
probe_mode="${4:-canonical}"
probe_directory="$(mktemp -d /private/tmp/powder-consultation-probe.XXXXXX)"
sdk_directory="$(xcrun --sdk macosx --show-sdk-path)"
machine_architecture="$(uname -m)"
engine_products="$engine_build/out/Products/Release"
intelligence_products="$intelligence_build/out/Products/Debug"
module_map="$engine_build/out/Intermediates.noindex/GeneratedModuleMaps/CBridge.modulemap"

mkdir -p "$evidence_directory" "$probe_directory/Inputs" "$probe_directory/module-cache"
print "PROBE_BUILD_DIRECTORY=$probe_directory"
for source in SceneAssistant AppleScenePlanner AppleSceneLayout SceneReferenceLibrary; do
  cp "$native_directory/App/Intelligence/$source.swift" "$probe_directory/Inputs/$source.swift"
done
cp "$native_directory/scripts/probe-scene-consultation.swift" "$probe_directory/Inputs/Probe.swift"
cp "$native_directory/scripts/SceneProbeGeometry.swift" "$probe_directory/Inputs/SceneProbeGeometry.swift"
shasum -a 256 "$probe_directory"/Inputs/*.swift > "$evidence_directory/canonical-source-sha256.txt"

# This diagnostic accessor is appended only to the copied file because the
# generated consultation type is private. No provider function is modified.
cat >> "$probe_directory/Inputs/SceneAssistant.swift" <<'SWIFT'

@available(macOS 26.4, *)
func consultationProbeSchemaTokenCount(proposalRequested: Bool = false) async throws -> Int {
    try await SystemLanguageModel.default.tokenCount(for: proposalRequested ? AppleDesignProposal.generationSchema : AppleConsultation.generationSchema)
}

@available(macOS 26.0, *)
func consultationProbeMinimalResponse(_ turns: [SceneConversationTurn], instructions: String) async throws -> SceneConsultation {
    let transcript = turns.map { "\($0.role.rawValue.uppercased()): \($0.text)" }.joined(separator: "\n\n")
    let session = LanguageModelSession(instructions: instructions)
    return try await session.respond(to: transcript, generating: AppleConsultation.self,
        options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 1_800)).content.value
}
SWIFT

xcrun swiftc -swift-version 6 -O -parse-as-library \
  -target "$machine_architecture-apple-macos26.0" -sdk "$sdk_directory" \
  -module-cache-path "$probe_directory/module-cache" \
  -I "$engine_products" -I "$intelligence_products" \
  -Xcc "-fmodule-map-file=$module_map" \
  "$probe_directory"/Inputs/*.swift \
  "$engine_products/PowderCore.o" "$engine_products/PowderEngine.o" \
  "$engine_products/CBridge.o" "$engine_products/JsonCpp.o" \
  "$intelligence_products/PowderIntelligence.o" \
  -lc++ -lbz2 -o "$probe_directory/probe-scene-consultation"

print "$probe_directory/probe-scene-consultation" > "$evidence_directory/probe-binary-path.txt"
"$probe_directory/probe-scene-consultation" "$evidence_directory" "$probe_mode" \
  2>&1 | tee "$evidence_directory/live-probe.log"
