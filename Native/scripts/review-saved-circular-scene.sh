#!/bin/zsh
set -euo pipefail
native_directory="${0:A:h:h}"
evidence_directory="${1:?Pass the directory containing the saved plan.json}"
engine_build="${2:-/private/tmp/powder-layout-engine-release}"
review_directory="$(mktemp -d /private/tmp/powder-saved-scene-review.XXXXXX)"
engine_products="$engine_build/out/Products/Release"
module_map="$engine_build/out/Intermediates.noindex/GeneratedModuleMaps/CBridge.modulemap"
xcrun swiftc -swift-version 6 -O -parse-as-library \
  -target "$(uname -m)-apple-macos14.0" -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$review_directory/module-cache" -I "$engine_products" \
  -Xcc "-fmodule-map-file=$module_map" \
  "$native_directory/scripts/SceneProbeGeometry.swift" "$native_directory/scripts/review-saved-circular-scene.swift" \
  "$engine_products/PowderCore.o" "$engine_products/PowderEngine.o" \
  "$engine_products/CBridge.o" "$engine_products/JsonCpp.o" -lc++ -lbz2 \
  -o "$review_directory/review-saved-scene"
"$review_directory/review-saved-scene" "$evidence_directory" 2>&1 | tee "$evidence_directory/geometry-review.log"
