#!/bin/zsh
set -euo pipefail

native_directory="${0:A:h:h}"
evidence_directory="${1:-${native_directory:h}/evidence/on-device-engine-v3}"
scene_prompt="${2:-Create a glass tank with water, sand above the water, and room for the sand to fall}"
build_directory="${3:-/private/tmp/powder-engine-build}"
probe_directory="$(mktemp -d /tmp/powder-engine-scene-probe.XXXXXX)"
sdk_directory="$(xcrun --sdk macosx --show-sdk-path)"
machine_architecture="$(uname -m)"

mkdir -p "$evidence_directory" "$probe_directory/module-cache" "$probe_directory/Inputs"
print "PROBE_BUILD_DIRECTORY=$probe_directory"
cp "$native_directory/App/Intelligence/AppleScenePlanner.swift" "$probe_directory/Inputs/AppleScenePlanner.swift"
cp "$native_directory/App/Intelligence/AppleSceneLayout.swift" "$probe_directory/Inputs/AppleSceneLayout.swift"
cp "$native_directory/scripts/probe-engine-scene-generation.swift" "$probe_directory/Inputs/Probe.swift"
shasum -a 256 "$probe_directory/Inputs/AppleScenePlanner.swift" "$probe_directory/Inputs/AppleSceneLayout.swift" \
  > "$evidence_directory/on-device-engine-v3-provider-sha256.txt"

# SwiftPM can use Xcode's build system or its ordinary command-line layout.
# Link the already tested package artifacts; do not replace the engine with mocks.
typeset -a link_inputs
if [[ -f "$build_directory/debug/PowderEngine.o" ]]; then
  module_directory="$build_directory/debug"
  module_map="$build_directory/out/Intermediates.noindex/GeneratedModuleMaps/CBridge.modulemap"
  link_inputs=("$module_directory/PowderCore.o" "$module_directory/PowderEngine.o" \
               "$module_directory/CBridge.o" "$module_directory/JsonCpp.o")
else
  module_directory="$build_directory/$machine_architecture-apple-macosx/debug/Modules"
  object_directory="${module_directory:h}"
  module_map="$object_directory/CBridge.build/module.modulemap"
  link_inputs=("$object_directory"/{PowderCore,PowderEngine,CBridge,JsonCpp}.build/**/*.o(N))
fi
if [[ ! -f "$module_map" || ${#link_inputs} -eq 0 ]]; then
  print -u2 "Build PowderEngine with swift test --scratch-path $build_directory before running this probe."
  exit 2
fi

xcrun swiftc -swift-version 6 -O -parse-as-library \
  -target "$machine_architecture-apple-macos26.0" -sdk "$sdk_directory" \
  -module-cache-path "$probe_directory/module-cache" -I "$module_directory" \
  -Xcc "-fmodule-map-file=$module_map" \
  "$probe_directory/Inputs/AppleScenePlanner.swift" "$probe_directory/Inputs/AppleSceneLayout.swift" "$probe_directory/Inputs/Probe.swift" \
  "${link_inputs[@]}" -lc++ -lbz2 -o "$probe_directory/probe-engine-scene-generation"

"$probe_directory/probe-engine-scene-generation" "$evidence_directory" "$scene_prompt" \
  2>&1 | tee "$evidence_directory/on-device-engine-v3.log"
