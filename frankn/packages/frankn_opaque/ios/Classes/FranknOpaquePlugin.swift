import Flutter
import UIKit

public class FranknOpaquePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    // Keep the C FFI shim and Rust symbols linked into the app for Dart FFI.
    frankn_opaque_ios_string_free(nil)
  }
}
