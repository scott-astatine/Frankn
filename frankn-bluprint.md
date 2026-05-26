# Frankn: My Personal Remote Ops Center

This is the evolving master plan and technical blueprint for **Frankn**, a high-performance, peer-to-peer remote operations center. I am building this because I need a secure, low-latency "remote brain" for my workstation and system servers—something that combines the power of a modern GUI with the absolute control of a terminal, without compromising on security or performance.

---

## 1. Vision & Core Design Principles

Unlike traditional remote administration interfaces, Frankn operates strictly on a set of core principles optimized for decentralized, lightweight execution:

1. **Intents, Not Pixels:** Frankn completely avoids bandwidth-heavy screen streaming (such as VNC or RDP). Instead, it streams raw, structured *intents* (binary file chunks, process metrics, system states, and terminal strings) across direct P2P data channels. This ensures that the interface remains blazingly fast even on degraded edge connections while conserving battery.
2. **Zero-Trust Security & Timing Mitigation:** Every connection is treated as hostile until cryptographically verified. We employ Argon2id challenge-response handshakes combined with constant-time verification primitives (`subtle` crate) to safeguard the pairing from side-channel timing analysis. Subsystem actions are sandboxed within the host's home directory (`dirs::home_dir()`), walking ancestor paths recursively to block directory traversal attacks.
3. **The Cyberpunk Aesthetic:** Built with a high-contrast monospaced command-line layout, Nerd Font iconography, neon borders, and dynamic frosted-glass modal panels, the client provides the visual feedback of an immersive, futuristic system cockpit.

---

## 2. Architecture Overview

Direct P2P links are negotiated dynamically via WebRTC, bypassing the need for port forwarding, public network exposure, or central VPN tunnels.

```
┌─────────────────────────────────┐           ┌─────────────────────────────────┐
│         FLUTTER CLIENT          │◄─────────►│            RUST HOST            │
│         (Mobile App)            │  WebRTC   │        (System Daemon)          │
│   Immersive Command Terminal    │           │   Direct D-Bus & Linux APIs     │
└─────────────────────────────────┘           └─────────────────────────────────┘
                 │                                             │
                 └──────────►┌─────────────────────────┐◄──────┘
                             │  RUST SIGNALING SERVER  │
                             │   (Secure Handshakes)   │
                             └─────────────────────────┘
```

### Comms Channels
* **specialized Data Lanes:**
  * `frankn_cmd`: System diagnostics, process managers, and power states.
  * `frankn_fs`: High-speed binary storage transfers with recursive indexing and SHA-256 validation.
  * `frankn_media`: Bidirectional MPRIS track status synchronization and interactive seek control.
  * `frankn_ssh`: Raw terminal bridge backed by sticky modifier mapping and cache-held session restoration.
  * `frankn_input`: batch-transmitted pointer movements, precise scroll metrics, and virtual key mapping.
  * `dohee_x`: Real-time streaming thread connecting to a secure, host-side AI chat engine (`llama-server`).
* **Discovery Protocol:** High-performance Signaling middleman that facilitates ICE exchanges, verifies unlisted hosts, restricts duplicate registrations, and enforces strict connection timeouts (15s/30s) to prune ghost sockets.
* **Persistent Configuration:** Workstation preferences are managed via a robust, custom path TOML engine and an interactive terminal-based TUI configurator with Vim-style navigation.

---

## 3. Current Development Progress

### A. Frankn-Host Server (Rust Daemon)
* **Security & Sandboxing:** Constant-time Argon2id verifiers, automatic legacy configuration upgrades on startup, and ancestor-validated path sandbox validation inside `fs_sync/mod.rs` to allow deep folder generation during transfers.
* **Workstation Integration:** Direct bindings to systemd, loginctl, D-Bus notification structures, and Hyprlock background child management.
* **Media & Audio Mixer:** Volume controls mapped directly to WirePlumber or PulseAudio mixers (`wpctl`/`pactl`) with strict floating-point amplitude safety clamps.
* **Storage Synchronizations:** Multi-threaded, symlink-aware directory indexing and sequential batch transfers backed by `notify` system directory monitors.
* **Local LLM Engine:** Host-side `LlmManager` orchestrating model selection, persistent session mapping (`chats.json`), and server-sent stream buffering.

### B. Flutter Mobile Client
* **Custom Scoped Storage Bypass:** Integrated a custom pure-Dart `LocalDirSelector` modal sheet to bypass scoped storage tree chooser freezes, facilitating sub-millisecond local folder and file traversals.
* **Default Path Configuration:** Configurable default download directory on the settings screen, allowing users to choose or clear a default landing path, with support for prompting on-demand destination selection for specific files.
* **Frosted Glassmorphic Context Sheets:** High-fidelity bottom sheets utilizing frosted blurs (`BackdropFilter`), cyan neon rails, dynamic monospaced diagnostics rows (file size, category, and local source indicators), and cybernetic icon buttons.
* **Interactive Media Deck:** Overhauled the music progress bar with a `LayoutBuilder` and horizontal drag-and-tap gestures to seek audio tracks dynamically via real-time `DcMsgSeek` updates.
* **Throttled Diagnostic Notifications:** Native notification progress redraw limits (500ms / 2Hz threshold) to prevent Dart-to-Native IPC thread lockups during high-speed transfers.
* **Precision Trackpad Gestures:** Batched touch gestures including 1-finger long-press for left-click dragging, 3-finger taps for middle-clicking, and dual-state HUD modifier key toggling/locking.

---

## 4. Phase Roadmap & Milestones

### Phase 1: Foundation & Zero-Trust Protocol [COMPLETE]
- [x] Adopted Argon2id cryptography for challenge-response auth verification.
- [x] Sandboxed path operations within secure user directories.
- [x] Hardened discovery server against peer hijacking and socket duplicates.
- [x] Implemented RAII connection cleanup routines to purge stale file descriptors.

### Phase 2: Core Workstation Node control [COMPLETE]
- [x] Power managers, systemctl states, and Hyprlock integration.
- [x] High-precision touch trackpad gestures and HUD modifier keys.
- [x] Dynamic, auto-scrolling terminal logs console preview.

### Phase 3: Storage Orchestration & Media [COMPLETE]
- [x] Recursive, symlink-aware filesystem indexing and editor viewers.
- [x] Chunked storage transfers with SHA-256 validations.
- [x] High-fidelity media track updates, volume mixers, and interactive seek scrubbers.

### Phase 4: Configurations & Handshakes [COMPLETE]
- [x] TOML-based persistence configurations and Vim-based config TUI.
- [x] QR code automated pairing, manual 12-digit IDs, and screen import decoders.
- [x] Discovery filtering to support unlisted host registries.

### Phase 5: Advanced Features & Synchronizations [IN PROGRESS]
- [x] **Notification Mirroring:** PC notification sync mirrors onto phone.
- [x] **Folder Mirroring:** Sequenced batch folder synchronizations with packet-size chunking (200 files per packet) and stack-based local scanning.
- [x] **Mobile SAF Bypass:** Pure-Dart local selector to avoid native tree chooser freezes.
- [x] **Settings Download Configs:** Default path preference controls and on-demand file destination routing.
- [x] **Visual Theme Hardening:** Frosted glassmorphism panels, cyan neon outlines, and icon-based command controls.
- [ ] **Neural Assistant:** Direct model selectors, chat stream buffering, and session logging [WIP].
- [ ] **Reverse Control:** Option to command the mobile node from the workstation terminal.

---

*Last Updated: Late May 2026*
