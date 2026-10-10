#!/bin/bash
set -euo pipefail
PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="$(cd "$PLUGIN_DIR/../../.." && pwd)"
CRATE_DIR="$REPO_DIR/frankn-opaque"
OUT_DIR="$PLUGIN_DIR/ios/Frameworks/FranknOpaque.xcframework"

for target in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
  rustup target add "$target"
  cargo build --manifest-path "$CRATE_DIR/Cargo.toml" --release --target "$target"
done
xcodebuild -create-xcframework \
  -library "$CRATE_DIR/target/aarch64-apple-ios/release/libfrankn_opaque.a" \
  -library "$CRATE_DIR/target/aarch64-apple-ios-sim/release/libfrankn_opaque.a" \
  -library "$CRATE_DIR/target/x86_64-apple-ios/release/libfrankn_opaque.a" \
  -output "$OUT_DIR"
