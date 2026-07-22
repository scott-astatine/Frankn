# ⚡ Frankn Flutter Client

The **Frankn Client** is a cross-platform (Android, Linux Desktop, macOS, Windows) command center application for managing workstation telemetry, remote terminal sessions, file transfers, and system media over end-to-end encrypted WebRTC P2P data channels.

---

## 📸 Key Screens & Subsystems

* **Frankn Dashboard (`frankn_dashboard.dart`)**: Real-time CPU, RAM, Network telemetry, quick launch shortcuts, and connected host status panels.
* **Markdown Viewer (`markdown_viewer_screen.dart`)**:
  * **Native Mermaid Vector Engine (`neo_mermaid_widget.dart`)**: Zero-webview native vector diagram renderer with interactive multi-touch pinch-to-zoom, dynamic sizing, and a full-screen zoom modal.
  * **LaTeX Support (`flutter_markdown_latex`)**: Renders inline `$ ... $` and block `$$ ... $$` math equations.
  * **Cyberpunk Dark Alert Boxes**: Dark glass containers (`AppColors.surfaceSecondary` 60% opacity) with glowing left warning accent border (`AppColors.accentWarning`), 6px rounded corners, and crisp typography.
* **Code Editor (`code_editor_screen.dart`)**: High-performance code editor powered by `re_editor` with syntax highlighting, auto-hiding `SliverAppBar` glassy header, and local file saving.
* **SSH Terminal (`ssh_screen.dart`)**:
  * **Persistent Session Restoration**: Navigating back via mobile gesture keeps the active WebRTC SSH tunnel, socket bridge, and terminal buffer alive in background memory.
  * **Trackpad-Identical Modifier HUD**: `CTRL`, `ALT`, `SHIFT` buttons with single-tap sticky mode (cyan glow) and double-tap permanent lock mode (purple accent glow).
  * **Explicit Disconnect**: Dedicated red `EXIT` HUD button to terminate the shell.
* **Precision Trackpad (`trackpad_screen.dart`)**: Multi-touch trackpad supporting 1-finger long-press drags, 3-finger middle clicks, custom sensitivity controls, and virtual Linux uinput key mappings.
* **File Browser (`file_browser_screen.dart`)**: High-speed remote directory navigation with custom download landing targets, sub-millisecond async folder listings, and frosted context sheets.
* **Process Manager (`process_manager_screen.dart`)**: Real-time process listing sorted by CPU/RAM usage with kill signals.

---

## 📖 Android `ACTION_VIEW` File Reader Integration

Frankn registers as a native file opener on Android (`AndroidManifest.xml` & `MainActivity.kt`). Opening files (`.md`, `.txt`, `.json`, `.yaml`, `.py`, `.rs`, `.dart`, etc.) from external file managers or email attachments routes intent payloads directly into Frankn's `MarkdownViewerScreen` or `CodeEditorScreen`.

---

## 🛠️ Build & Development Setup

### Prerequisites
* Flutter SDK (3.8+)
* Bun / Node.js (for asset & web tooling)

### Run locally
```bash
flutter pub get
flutter run
```

### Run Static Analysis
```bash
flutter analyze
```

---

*Part of the Frankn Remote Operations Center project.*
