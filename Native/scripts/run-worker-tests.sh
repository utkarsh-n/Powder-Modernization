#!/bin/zsh
set -euo pipefail

# Compile the actual worker/session and their XCTest files without starting NSApplication.
# The small temporary package avoids launching the hosted macOS UI test application.
native_directory="${0:A:h:h}"
harness_directory="${1:-/private/tmp/powder-worker-test-harness}"
cache_directory="/private/tmp/powder-worker-test-module-cache"
mkdir -p "$harness_directory/Sources/Powder" "$harness_directory/Tests/PowderTests" "$cache_directory"

sources=(App/SimulationWorker.swift App/PlaygroundSession.swift App/StudioScenes.swift
  App/Rendering/MetalFrame.swift App/Rendering/MaterialAppearance.swift
  App/Design/MaterialPresentation.swift App/Design/MaterialSymbolCatalog.swift
  App/Design/MaterialSymbolTint.swift App/CurrentBrushSwatch.swift)
extra_dependencies=""
extra_products=""
if [[ "${2:-}" == "--include-ai" ]]; then
  sources+=(App/Intelligence/SceneIntelligence.swift App/Intelligence/SceneAssistant.swift
    App/Intelligence/SceneCandidateBuilder.swift App/Intelligence/SceneReferenceLibrary.swift
    App/Intelligence/CloudCredentialStore.swift App/Intelligence/AppleScenePlanner.swift
    App/Intelligence/AppleSceneLayout.swift App/Intelligence/LocalSceneAssistant.swift
    App/Intelligence/ResilientSceneAssistant.swift)
  extra_dependencies=", .package(path: \"$native_directory/Packages/PowderIntelligence\")"
  extra_products=", .product(name: \"PowderIntelligence\", package: \"PowderIntelligence\")"
  cp "$native_directory/Tests/SceneIntelligenceTests.swift" "$harness_directory/Tests/PowderTests/"
  cp "$native_directory/Tests/LocalSceneAssistantTests.swift" "$harness_directory/Tests/PowderTests/"
  cp "$native_directory/Tests/ResilientSceneAssistantTests.swift" "$harness_directory/Tests/PowderTests/"
fi
for source in "${sources[@]}"; do
  cp "$native_directory/$source" "$harness_directory/Sources/Powder/${source:t}"
done
cp "$native_directory/Tests/SimulationWorkerTests.swift" "$harness_directory/Tests/PowderTests/"
cp "$native_directory/Tests/PlaygroundSessionTests.swift" "$harness_directory/Tests/PowderTests/"

# Explicit file lists keep a later focused run independent of optional AI copies.
source_list=""
for source in "${sources[@]}"; do source_list+="\"${source:t}\","; done
test_list='"SimulationWorkerTests.swift", "PlaygroundSessionTests.swift"'
if [[ "${2:-}" == "--include-ai" ]]; then test_list+=', "SceneIntelligenceTests.swift", "LocalSceneAssistantTests.swift", "ResilientSceneAssistantTests.swift"'; fi

cat > "$harness_directory/Package.swift" <<EOF
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "PowderWorkerValidation", platforms: [.macOS(.v14)],
  dependencies: [.package(path: "$native_directory/Packages/PowderEngine"),
    .package(path: "$native_directory/Packages/PowderCore")$extra_dependencies],
  targets: [
    .target(name: "Powder", dependencies: [.product(name: "PowderEngine", package: "PowderEngine"),
      .product(name: "PowderCore", package: "PowderCore")$extra_products], sources: [$source_list]),
    .testTarget(name: "PowderTests", dependencies: ["Powder", .product(name: "PowderEngine", package: "PowderEngine"),
      .product(name: "PowderCore", package: "PowderCore")$extra_products], sources: [$test_list])
  ])
EOF

print "Production source hashes for this headless validation:"
for source in "${sources[@]}"; do shasum -a 256 "$native_directory/$source"; done
test_options=()
if [[ -n "${3:-}" ]]; then test_options=(--filter "$3"); fi
CLANG_MODULE_CACHE_PATH="$cache_directory" SWIFTPM_MODULECACHE_OVERRIDE="$cache_directory" \
  swift test --package-path "$harness_directory" --disable-sandbox \
  --scratch-path "$harness_directory/build" --jobs 4 "${test_options[@]}"
