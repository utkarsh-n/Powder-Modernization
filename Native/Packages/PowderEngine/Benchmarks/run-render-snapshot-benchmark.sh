#!/bin/zsh
set -euo pipefail

package_directory="${0:A:h:h}"
build_directory="${1:-/private/tmp/powder-engine-perf-build}"
output_directory="${2:-${package_directory:h:h:h}/evidence}"
compiler_cache="/private/tmp/powder-engine-benchmark-module-cache"
mkdir -p "$output_directory" "$compiler_cache"

CLANG_MODULE_CACHE_PATH="$compiler_cache" SWIFTPM_MODULECACHE_OVERRIDE="$compiler_cache" \
  swift build --package-path "$package_directory" --disable-sandbox \
    --scratch-path "$build_directory" -c release --jobs 8 \
    > "$output_directory/engine-render-snapshot-release-build.log" 2>&1

typeset -a link_inputs
if [[ -f "$build_directory/release/PowderEngine.o" ]]; then
  module_directory="$build_directory/release"
  module_map="$build_directory/out/Intermediates.noindex/GeneratedModuleMaps/CBridge.modulemap"
  link_inputs=("$module_directory/PowderCore.o" "$module_directory/PowderEngine.o" \
               "$module_directory/CBridge.o" "$module_directory/JsonCpp.o")
else
  architecture="$(uname -m)"
  object_directory="$build_directory/$architecture-apple-macosx/release"
  module_directory="$object_directory/Modules"
  module_map="$object_directory/CBridge.build/module.modulemap"
  link_inputs=("$object_directory"/{PowderCore,PowderEngine,CBridge,JsonCpp}.build/**/*.o(N))
fi

xcrun swiftc -swift-version 6 -O -parse-as-library \
  -module-cache-path "$compiler_cache" -I "$module_directory" \
  -Xcc "-fmodule-map-file=$module_map" \
  "$package_directory/Benchmarks/RenderSnapshotBenchmark.swift" "${link_inputs[@]}" \
  -lc++ -lbz2 -o "$build_directory/render-snapshot-benchmark"
"$build_directory/render-snapshot-benchmark" > "$output_directory/engine-render-snapshot-benchmark.json"
cat "$output_directory/engine-render-snapshot-benchmark.json"
