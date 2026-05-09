# Frankn: My Personal Remote Ops Center

This is the evolving master plan for **Frankn**, a high-performance, P2P remote operations center. I am building this because I need a "remote brain" for my personal AI assistant devices—something that combines the power of a terminal with the elegance of a modern GUI, without sacrificing security or privacy.

---

## 1. My Vision & Design Principles

I'm not just building another remote desktop app. Frankn is designed around three core pillars:

1. **Intents, Not Pixels**: Unlike VNC or RDP, Frankn doesn't stream your screen. It streams *intents* (commands, file chunks, metadata). This makes it blazingly fast even on slow connections and extremely light on battery.
2. **Zero-Trust Security**: Every connection is a stranger until proven otherwise. I've implemented a rigorous Argon2-based challenge-response protocol. If the host doesn't know you, the "Gatekeeper" doesn't even let your messages reach the system logic.
3. **The Cyberpunk Aesthetic**: If I'm going to control my life from a phone, it should look like it belongs in 2077. I'm using high-contrast neon accents, monospaced Nerd Fonts for iconography, and a terminal-first design language.

---

## 2. Architecture Overview

My architecture relies on **WebRTC** for direct, encrypted P2P communication, bypassing the need for port forwarding or VPNs.

```
┌─────────────────────────┐         ┌────────────────────────────┐
│     Flutter Mobile      │◄───────►│     Rust Backend           │
│     App (Client)        │ WebRTC  │     (System Service)       │
│                         │         │     Running on PC          │
└─────────────────────────┘         └────────────────────────────┘
          │                                             │
          └───────►┌──────────────────────┐◄────────────┘
                   │    Rust Signaling    │
                   │        Server        │
                   │      (Discovery)     │
                   └──────────────────────┘
```

### Comms
* **Transport**: Multi-channel WebRTC Data Channels. Specialized lanes: `frankn_cmd` (general ops), `frankn_fs` (file transfers), `frankn_media` (sync), `frankn_ssh` (terminal), **`dohee_x`** (LLM / neural chat streaming), and **`frankn_input`** (virtual keyboard & mouse events to the host).
* **Discovery**: A lightweight Rust Signaling Server facilitates initial handshakes (SDP/ICE exchange). Includes support for private/unlisted hosts and guards against duplicate peer registrations on a connection.
* **Config**: Host settings are managed via a persistent TOML provider and an interactive TUI.
* **Background Ops**: The mobile app runs a persistent Foreground Service on Android to maintain the link; RTC-heavy work is isolated from the UI isolate for stability.

---

## 3. Current Progress

### A. Frankn-Host Server
I've implemented a robust backend that interfaces directly with Linux system APIs:
- **Security**: Argon2id challenge-response. Host generates session challenges; client proves knowledge without sending passwords.
- **CLI/TUI**: A dedicated tool for configuration management (`frankn-host config`) and pairing (`frankn-host pair`) with QR code generation.
- **Power Management**: Integrated with `systemctl`, `loginctl`, and `hyprlock`.
- **Media & Audio**: Full audio mixer experience (`wpctl`/`pactl`) and track control (`mpris`).
- **File System**: Recursive viewing, chunked transfers with SHA-256 validation, and integrated editor.
- **Neural / LLM**: `LlmManager` handles chat sessions, streaming inference (including SSE-style upstream handling), and persistence; exposes commands over the `dohee_x` data channel inside the authenticated WebRTC session.
- **Remote Input**: Optional `uinput`-based virtual mouse and keyboard; fails soft at startup if the kernel module or `/dev/uinput` permissions are missing, leaving other ops unaffected.

### B. The "interface" (Flutter Client)
The UI is now highly functional and visually polished:
- **Immersive Terminal**: Full-screen SSH via `dartssh2` and `xterm.dart` with Nerd Font support.
- **SSH Session Restore**: Seamless, in-memory credential caching for instant terminal re-entry during the same host session.
- **Pairing System**: QR Code scanner (including screenshot import) and manual 12-digit ID entry for persistent "Hosts"
- **File Browser**: Refactored for speed with real-time progress bars and bulk actions.
- **Notification Mirroring**: Linux D-Bus notifications pushed to mobile via `awesome_notifications`.
- **Dynamic Settings**: Persistent app configuration (Signaling URL, font size, themes).
- **Neural Deck (Dohee)**: In-app LLM chat with streaming markdown/LaTeX-style rendering; pairs with the host `dohee_x` channel and model selection.
- **Remote Trackpad**: Redesigned full-screen touch trackpad with batched move/scroll, sticky modifiers, and a dynamic toolbar that appears only when typing—fixed Linux keycode mapping for perfect input accuracy.
- **Shell UX**: SSH controller / key bar refinements and clearer connection status affordances.
- **Live Log Deck**: A real-time, auto-scrolling log preview widget docked to the bottom of the host list for instant diagnostic visibility.

### C. Recent milestones (early 2026)
Shipped or in flight alongside the blueprint updates:
- **Local LLM path on the host** (`LlmManager`): chat sessions persisted under `~/.config/frankn/chats.json`, streaming responses to the client (SSE-style consumption on the host, forwarded over WebRTC).
- **Background isolate migration** for WebRTC: keeps the UI responsive and reduces link “zombie” races during reconnect.
- **Signaling Security & Persistence**: Identity hijacking prevention and strict 15s/30s `last_seen` timeouts to purge ghost connections.
- **Custom Configuration Paths**: Host-side support for specifying config files via the `-c` flag.
- **Stable FS streaming**: Chunked transfer and media pipeline hardening on the host.
- **Linux virtual input**: Corrected `uinput` keycode mappings and improved error diagnostics for system-level permission failures.

---

## 4. Modification History & Progress

### Phase 1: Security & Foundation [COMPLETE]
- [x] Switched to Argon2id for industry-standard password hashing.
- [x] Implemented the "Gatekeeper" pattern to enforce authenticated sessions.
- [x] Added timestamp-based signaling to prevent replay attacks.
- [x] Established robust mixin-based RTC client architecture.
- [x] Hardened signaling server against identity hijacking and ghost connections.

### Phase 2: Core Control [COMPLETE]
- [x] Real-world system calls for Power, Media, and Processes.
- [x] Bi-directional state sync: Host pushes media updates (title, art, position).
- [x] Immersive full-screen Terminal with context menu.
- [x] Settings page for configuration management.

### Phase 3: Files & Media [COMPLETE]
- [x] Recursive File Browser with symlink support.
- [x] Robust chunked file transfer with SHA-256 integrity checks.
- [x] Integrated Linux System Logs (`journalctl`) into a dedicated mobile view.
- [x] Advanced Media Sync: HTTP remote album art support and immediate state synchronization.

### Phase 4: Configuration & Pairing [COMPLETE]
- [x] **Config Provider**: Persistent TOML-based host settings with custom path support.
- [x] **Host TUI**: Cyberpunk-styled terminal UI for managing settings with Vim keybinds.
- [x] **QR Pairing**: Automated pairing flow via QR scanning, screenshot import, and 12-digit unique IDs.
- [x] **Discovery Filtering**: Support for unlisted/private hosts.

### Phase 5: Advanced Features [IN PROGRESS]
- [x] **Notification Mirroring**: PC notifications buzz on the phone.
- [x] **Neural Chat & LLM over WebRTC**: Dedicated `dohee_x` data channel with host-side `LlmManager` (local inference / streaming, chat persistence)—same zero-trust session as the rest of Frankn; no need to expose model APIs publicly.
- [x] **Remote Trackpad & Keyboard**: `frankn_input` channel + Linux `uinput` for pointer, scroll, keys, and typed text from the mobile client. Corrected Linux keycode translation logic.
- [x] **SSH Session Restore**: Secure, in-memory credential restoration for seamless terminal entry.
- [x] **Live Log Preview**: Docked scrolling widget for instant signaling and system diagnostic monitoring.
- [ ] **Vice Versa**: PC controlling the phone (Mobile as the Host).
- [ ] **Bidirectional Sync**: Folder-to-folder background synchronization.
- [x] **Process Manager Search**: Advanced filtering for the process list.

---

## 5. Why I'm Building This (Comparison)
* Aesthetic mobile-centric ROC for local & remote servers.
*   **vs SSH/Termux**: Frankn provides a native GUI for quick tasks like volume control while keeping the power of a terminal.
*   **vs Remote Desktop (RDP/VNC)**: Frankn works on poor connections because it streams metadata, not video buffers.
*   **vs KDE Connect**: Frankn works over the global internet via WebRTC, not just local Wi-Fi. And it's just better!


---
*Last Updated: May 2026*
