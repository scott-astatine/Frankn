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

┌─────────────────────────┐         ┌────────────────────────────┐
│     Flutter Mobile      │◄───────►│     Rust Backend           │
│     App (Client)        │ WebRTC  │     (System Service)       │
│                         │         │     Running on PC          │
└─────────────────────────┘         └────────────────────────────┘
          │                                             │
          └───────►┌──────────────────────┐◄────────────┘
                   │    Rust Signaling    │
                   │        Server        │
                   │                      │
                   │      (Discovery)     │
                   └──────────────────────┘

### Comms
* **Transport**: Multi-channel WebRTC Data Channels. Specialized lanes: `frankn_cmd` (general ops), `frankn_fs` (file transfers), `frankn_media` (sync), and `frankn_ssh` (terminal).
* **Discovery**: A lightweight Rust Signaling Server facilitates initial handshakes (SDP/ICE exchange). Includes support for private/unlisted hosts.
* **Config**: Host settings are managed via a persistent TOML provider and an interactive TUI.
* **Background Ops**: The mobile app runs a persistent Foreground Service on Android to maintain the link.

---

## 3. Current Progress

### A. Frankn-Host Server
I've implemented a robust backend that interfaces directly with Linux system APIs:
- **Security**: Argon2id challenge-response. Host generates session challenges; client proves knowledge without sending passwords.
- **CLI/TUI**: A dedicated tool for configuration management (`frankn-host config`) and pairing (`frankn-host pair`) with QR code generation.
- **Power Management**: Integrated with `systemctl`, `loginctl`, and `hyprlock`.
- **Media & Audio**: Full audio mixer experience (`wpctl`/`pactl`) and track control (`mpris`).
- **File System**: Recursive viewing, chunked transfers with SHA-256 validation, and integrated editor.

### B. The "interface" (Flutter Client)
The UI is now highly functional and visually polished:
- **Immersive Terminal**: Full-screen SSH via `dartssh2` and `xterm.dart` with Nerd Font support.
- **Pairing System**: QR Code scanner and manual 12-digit ID entry for persistent "Neural Links."
- **File Browser**: Refactored for speed with real-time progress bars and bulk actions.
- **Notification Mirroring**: Linux D-Bus notifications pushed to mobile via `awesome_notifications`.
- **Dynamic Settings**: Persistent app configuration (Signaling URL, font size, themes).

---

## 4. Modification History & Progress

### Phase 1: Security & Foundation [COMPLETE]
- [x] Switched to Argon2id for industry-standard password hashing.
- [x] Implemented the "Gatekeeper" pattern to enforce authenticated sessions.
- [x] Added timestamp-based signaling to prevent replay attacks.
- [x] Established robust mixin-based RTC client architecture.

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
- [x] **Config Provider**: Persistent TOML-based host settings.
- [x] **Host TUI**: Cyberpunk-styled terminal UI for managing settings with Vim keybinds.
- [x] **QR Pairing**: Automated pairing flow via QR scanning and 12-digit unique IDs.
- [x] **Discovery Filtering**: Support for unlisted/private hosts.

### Phase 5: Advanced Features [IN PROGRESS]
- [x] **Notification Mirroring**: PC notifications buzz on the phone.
- [ ] **Vice Versa**: PC controlling the phone (Mobile as the Host).
- [ ] **Bidirectional Sync**: Folder-to-folder background synchronization.
- [ ] **Process Manager Search**: Advanced filtering for the process list.

---

## 5. Why I'm Building This (Comparison)
* Aesthetic mobile-centric ROC for local & remote servers.
*   **vs SSH/Termux**: Frankn provides a native GUI for quick tasks like volume control while keeping the power of a terminal.
*   **vs Remote Desktop (RDP/VNC)**: Frankn works on poor connections because it streams metadata, not video buffers.
*   **vs KDE Connect**: Frankn works over the global internet via WebRTC, not just local Wi-Fi.

## 6. TODO
### [ ] Fix Firefox MediaUpdate showing up even when other players (Spotify) are active.
### [ ] Implement host config CLI/GUI installer script.
### [x] Implement Host config TUI.
### [x] Fix Notification sync reliability.
### [x] FIX Download notification showing up when opening files in the editor.
### [x] FIX Download/Upload progress bar (accurate percentages).
### [x] FIX Reconnection race conditions and "zombie" links.
### [ ] Make the quick functions/commands more modular (Plugin system?).

---
*Last Updated: February 2026*