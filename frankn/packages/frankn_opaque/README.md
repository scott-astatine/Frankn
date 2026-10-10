# frankn_opaque

The package uses the shared RFC 9807 implementation in `../../../frankn-opaque`.
It supports Android and iOS. Android installs the Rust targets and builds the
shared library for ARM64, ARMv7, and x86_64 with `cargo-ndk` and Android NDK
installed. iOS builds a
device and simulator XCFramework during CocoaPods preparation; it requires
Xcode and the `aarch64-apple-ios`, `aarch64-apple-ios-sim`, and `x86_64-apple-ios`
Rust targets.

The Dart API only marshals opaque protocol messages and invokes the native core.
The passcode and derived session credential stay in process memory and are
zeroed where mutable buffers are available. The signaling/WebRTC layer sees
only the encoded OPAQUE request, response, and finalization.
