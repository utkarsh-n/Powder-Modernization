#!/bin/zsh
set -euo pipefail
native_dir="${0:A:h:h}"
builds_dir="$native_dir/../Builds"
source_app="${POWDER_MAC_APP:-$native_dir/DerivedData/Build/Products/Release/Powder.app}"
stage_dir=$(mktemp -d /private/tmp/powder-v6.2-package.XXXXXX)
check_dir=$(mktemp -d /private/tmp/powder-v6.2-release-check.XXXXXX)
mkdir -p "$builds_dir"
# Keep packaging outside iCloud-managed Documents, which adds Finder metadata to .app bundles.
ditto --norsrc --noextattr --noqtn "$source_app" "$stage_dir/Powder.app"
codesign --force --sign - --timestamp=none "$stage_dir/Powder.app"
codesign --verify --deep --strict --verbose=2 "$stage_dir/Powder.app"
lipo -archs "$stage_dir/Powder.app/Contents/MacOS/Powder"
ditto -c -k --keepParent "$stage_dir/Powder.app" "$builds_dir/Powder-macOS-v0.6.2-universal.zip"
ditto -x -k "$builds_dir/Powder-macOS-v0.6.2-universal.zip" "$check_dir"
codesign --verify --deep --strict --verbose=2 "$check_dir/Powder.app"
cp "$builds_dir/Powder-macOS-v0.6.2-universal.zip" "$builds_dir/Powder-macOS-universal.zip"
print -r -- "$check_dir/Powder.app"
