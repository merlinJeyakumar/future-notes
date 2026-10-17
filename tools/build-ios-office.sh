#!/usr/bin/env bash
set -euo pipefail

# Execute on macOS with Xcode selected. Never replaces an accepted framework.
[[ "$(uname -s)" == Darwin ]] || { echo 'A Mac with Xcode is required.' >&2; exit 1; }
project_root="$(cd "$(dirname "$0")/.." && pwd)"
source_root="$project_root/.validation/office-oxide-source"
build_root="$project_root/.native-deps/office-oxide/ios"
destination="$project_root/ios/OfficeOxide/OfficeOxide.xcframework"
commit=5d183f4de990de254f32976bf952e548bcd25972
[[ ! -e "$destination" ]] || { echo 'Preserve/archive the existing framework before rebuilding.' >&2; exit 1; }
if [[ ! -d "$source_root" ]]; then
  git clone --depth 1 --branch v0.1.15 https://github.com/yfedoseev/office_oxide.git "$source_root"
fi
[[ "$(git -C "$source_root" rev-parse HEAD)" == "$commit" ]] || { echo 'Office source pin mismatch.' >&2; exit 1; }
[[ -z "$(git -C "$source_root" status --porcelain)" ]] || { echo 'Office source contains modifications.' >&2; exit 1; }
export IPHONEOS_DEPLOYMENT_TARGET=13.0
for target in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
  rustup target add "$target"
  cargo build --manifest-path "$source_root/Cargo.toml" --locked --release --no-default-features --lib --target "$target" --jobs 4
done
mkdir -p "$build_root"
xcrun lipo -create \
  "$source_root/target/aarch64-apple-ios-sim/release/liboffice_oxide.a" \
  "$source_root/target/x86_64-apple-ios/release/liboffice_oxide.a" \
  -output "$build_root/liboffice_oxide_simulator.a"
xcodebuild -create-xcframework \
  -library "$source_root/target/aarch64-apple-ios/release/liboffice_oxide.a" -headers "$source_root/include" \
  -library "$build_root/liboffice_oxide_simulator.a" -headers "$source_root/include" \
  -output "$destination"
mkdir -p "$project_root/.native-deps/office-oxide/licenses"
mkdir -p "$project_root/ios/OfficeOxide/Licenses"
for license in LICENSE-MIT LICENSE-APACHE NOTICE TRADEMARKS.md; do
  cp "$source_root/$license" "$project_root/.native-deps/office-oxide/licenses/$license"
  cp "$source_root/$license" "$project_root/ios/OfficeOxide/Licenses/$license"
done
echo "Built pinned Office Oxide 0.1.15: $destination"
