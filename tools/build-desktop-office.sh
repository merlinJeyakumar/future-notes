#!/usr/bin/env bash
set -euo pipefail

# Run on the destination desktop host. Do not substitute a cross-built/unproved
# ABI or overwrite an already accepted native artifact.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
source_root="$project_root/.validation/office-oxide-source"
commit=5d183f4de990de254f32976bf952e548bcd25972
host="$(uname -s)"
case "$host" in
  Darwin)
    destination="$project_root/macos/OfficeOxide/OfficeOxide.xcframework"
    licenses="$project_root/macos/OfficeOxide/Licenses"
    targets=(aarch64-apple-darwin x86_64-apple-darwin)
    for tool in xcodebuild xcrun; do command -v "$tool" >/dev/null; done
    xcode-select -p >/dev/null
    ;;
  Linux)
    command -v getconf >/dev/null
    getconf GNU_LIBC_VERSION >/dev/null 2>&1 || {
      echo 'This Linux recipe requires a GNU/glibc host; musl builds need their own validated package.' >&2; exit 1;
    }
    case "$(uname -m)" in
      x86_64) targets=(x86_64-unknown-linux-gnu) ;;
      aarch64|arm64) targets=(aarch64-unknown-linux-gnu) ;;
      *) echo 'Only native x86_64 and aarch64 GNU/Linux builds are supported by this recipe.' >&2; exit 1 ;;
    esac
    destination="$project_root/.native-deps/office-oxide/linux/${targets[0]}"
    licenses="$destination/Licenses"
    command -v nm >/dev/null
    ;;
  *) echo 'Run this desktop Office recipe on macOS or GNU/Linux.' >&2; exit 1 ;;
esac
[[ ! -e "$destination" && ! -e "$licenses" ]] || {
  echo 'Preserve/archive the existing desktop Office artifact before rebuilding.' >&2; exit 1;
}
for tool in git rustup cargo; do command -v "$tool" >/dev/null; done
if [[ ! -d "$source_root" ]]; then
  mkdir -p "$(dirname "$source_root")"
  git clone --depth 1 --branch v0.1.15 https://github.com/yfedoseev/office_oxide.git "$source_root"
fi
[[ "$(git -C "$source_root" rev-parse HEAD)" == "$commit" ]] || {
  echo 'Office source pin mismatch.' >&2; exit 1;
}
[[ -z "$(git -C "$source_root" status --porcelain)" ]] || {
  echo 'Office source contains modifications.' >&2; exit 1;
}
[[ -f "$source_root/Cargo.lock" && -f "$source_root/include/office_oxide_c/office_oxide.h" ]] || {
  echo 'The pinned Office source or lock is incomplete.' >&2; exit 1;
}
build_parent="$project_root/.native-deps/office-oxide/build"
mkdir -p "$build_parent"
build_root="$(mktemp -d "$build_parent/desktop.XXXXXXXX")"
# Failed builds remain isolated for diagnosis; accepted artifacts are untouched.
for target in "${targets[@]}"; do
  rustup target add "$target"
  if [[ "$host" == Darwin ]]; then
    # Apple Silicon's platform floor is 11.0. Intel preserves the app's 10.15 floor.
    if [[ "$target" == aarch64-* ]]; then export MACOSX_DEPLOYMENT_TARGET=11.0;
    else export MACOSX_DEPLOYMENT_TARGET=10.15; fi
  fi
  cargo build --manifest-path "$source_root/Cargo.toml" --locked --release \
    --no-default-features --lib --target "$target" --jobs 4
done
symbols=(office_document_open office_document_to_html office_document_free office_oxide_free_string)
if [[ "$host" == Darwin ]]; then
  universal="$build_root/liboffice_oxide.a"
  xcrun lipo -create \
    "$source_root/target/aarch64-apple-darwin/release/liboffice_oxide.a" \
    "$source_root/target/x86_64-apple-darwin/release/liboffice_oxide.a" -output "$universal"
  for arch in arm64 x86_64; do
    # Check native symbols while skipping newer LLVM bitcode for older Xcode inspectors.
    xcrun nm -arch "$arch" -g -U --no-llvm-bc "$universal" | awk '{print $NF}' > "$build_root/$arch.symbols"
    for symbol in "${symbols[@]}"; do grep -Fqx "_$symbol" "$build_root/$arch.symbols"; done
  done
  xcodebuild -create-xcframework -library "$universal" -headers "$source_root/include" \
    -output "$build_root/OfficeOxide.xcframework"
  mkdir -p "$build_root/Licenses"
  for license in LICENSE-MIT LICENSE-APACHE NOTICE TRADEMARKS.md; do
    cp "$source_root/$license" "$build_root/Licenses/$license"
  done
  mkdir -p "$(dirname "$destination")"
  # Recheck after compilation; another build must not replace an accepted output.
  [[ ! -e "$destination" && ! -e "$licenses" ]] || { echo 'Desktop Office output changed during build.' >&2; exit 1; }
  # Exclusive directory creation also refuses a concurrent builder's output.
  mkdir "$destination"
  mkdir "$licenses"
  cp -R "$build_root/OfficeOxide.xcframework/." "$destination/"
  cp -R "$build_root/Licenses/." "$licenses/"
else
  library="$source_root/target/${targets[0]}/release/liboffice_oxide.so"
  nm -D --defined-only "$library" | awk '{print $NF}' > "$build_root/linux.symbols"
  for symbol in "${symbols[@]}"; do grep -Fqx "$symbol" "$build_root/linux.symbols"; done
  mkdir -p "$build_root/output/Licenses"
  cp "$library" "$build_root/output/liboffice_oxide.so"
  for license in LICENSE-MIT LICENSE-APACHE NOTICE TRADEMARKS.md; do
    cp "$source_root/$license" "$build_root/output/Licenses/$license"
  done
  printf '%s\n' "$commit" > "$build_root/output/SOURCE_COMMIT"
  printf '%s\n' "${targets[0]}" > "$build_root/output/RUST_TARGET"
  mkdir -p "$(dirname "$destination")"
  [[ ! -e "$destination" ]] || { echo 'Desktop Office output changed during build.' >&2; exit 1; }
  mkdir "$destination"
  cp -R "$build_root/output/." "$destination/"
fi
echo "Built pinned Office Oxide 0.1.15: $destination"
