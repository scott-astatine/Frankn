package com.astatine.frankn_opaque

import io.flutter.embedding.engine.plugins.FlutterPlugin

/** FFI-only plugin. Rust symbols are exported by libfrankn_opaque.so. */
class FranknOpaquePlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) = Unit
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) = Unit
}
