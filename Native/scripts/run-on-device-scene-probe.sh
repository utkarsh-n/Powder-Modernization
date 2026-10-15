#!/bin/zsh
set -euo pipefail

native_directory="${0:A:h:h}"
evidence_directory="${1:-${native_directory:h}/evidence}"
scene_prompt="${2:-Build a battery connected by wire to a fuse next to explosives in a brick chamber}"
probe_directory="$(mktemp -d /tmp/powder-scene-probe.XXXXXX)"
sdk_directory="$(xcrun --sdk macosx --show-sdk-path)"
machine_architecture="$(uname -m)"
core_directory="$native_directory/Packages/PowderCore/Sources/PowderCore"

mkdir -p "$evidence_directory" "$probe_directory/module-cache" "$probe_directory/Inputs/Core"
print "PROBE_BUILD_DIRECTORY=$probe_directory"
cp "$core_directory"/*.swift "$probe_directory/Inputs/Core/"
cp "$native_directory/App/Intelligence/AppleScenePlanner.swift" "$probe_directory/Inputs/AppleScenePlanner.swift"
shasum -a 256 "$probe_directory/Inputs/AppleScenePlanner.swift" \
  > "$evidence_directory/on-device-scene-provider-sha256.txt"

xcrun swiftc -swift-version 6 -O -parse-as-library -emit-library -emit-module \
  -module-name PowderCore -target "$machine_architecture-apple-macos26.0" \
  -sdk "$sdk_directory" -module-cache-path "$probe_directory/module-cache" \
  "$probe_directory/Inputs/Core"/*.swift -emit-module-path "$probe_directory/PowderCore.swiftmodule" \
  -o "$probe_directory/libPowderCore.dylib"

xcrun swiftc -swift-version 6 -O -parse-as-library \
  -target "$machine_architecture-apple-macos26.0" -sdk "$sdk_directory" \
  -module-cache-path "$probe_directory/module-cache" -I "$probe_directory" -L "$probe_directory" \
  -lPowderCore -Xlinker -rpath -Xlinker "$probe_directory" \
  "$probe_directory/Inputs/AppleScenePlanner.swift" \
  "$native_directory/scripts/probe-scene-generation.swift" \
  -o "$probe_directory/probe-scene-generation"

"$probe_directory/probe-scene-generation" "$evidence_directory" "$scene_prompt" \
  2>&1 | tee "$evidence_directory/on-device-scene.log"
