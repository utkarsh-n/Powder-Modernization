#!/bin/zsh
set -euo pipefail
native_dir="${0:A:h:h}"
products="$native_dir/DerivedData/Build/Products/Release"
module_map="$native_dir/DerivedData/Build/Intermediates.noindex/GeneratedModuleMaps/CBridge.modulemap"
audit_dir=$(mktemp -d /private/tmp/powder-symbol-audit.XXXXXX)
xcrun swiftc -swift-version 6 -O -parse-as-library -target "$(uname -m)-apple-macos14.0" \
  -module-cache-path "$audit_dir/module-cache" -I "$products" -Xcc "-fmodule-map-file=$module_map" \
  "$native_dir/App/Design/MaterialSymbolCatalog.swift" "$native_dir/App/Design/MaterialSymbolTint.swift" \
  "$native_dir/scripts/verify-material-symbols.swift" \
  "$products/PowderEngine.o" "$products/PowderCore.o" "$products/CBridge.o" "$products/JsonCpp.o" \
  -lc++ -lbz2 -o "$audit_dir/verify"
"$audit_dir/verify" "$native_dir/../evidence/material-symbols-v52"
