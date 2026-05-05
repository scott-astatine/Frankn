# Frankn

Frankn is my personal modular Remote access tool for my servers & a personal assistant device that I'm working on. 

The core philosophy here is **Intents over Pixels**. Instead of streaming a video buffer, Frankn streams commands and metadata over direct WebRTC data channels. This makes it usable even on spotty mobile connections where VNC or RDP would just die.

## Architecture

The system is split into three parts:
- **Client (Flutter)**: My mobile interface—immersive SSH (`xterm`), file browser & editor, notification mirroring, neural chat UI, remote trackpad/keyboard, and QR-based pairing.
- **Host (Rust)**: The system-level service running on the PC. It talks to Linux APIs (systemd, D-Bus, MPRIS) and includes a CLI/TUI for configuration.
- **Signaling Server (Rust)**: A lightweight middleman used only for the initial WebRTC handshake (SDP/ICE exchange). Once connected, the traffic is strictly P2P.

## Superpowers (Features)

- **Immersive Terminal**: Full SSH access over WebRTC with session restoration. Supports Nerd Fonts and sticky modifier keys.
- **Zero-Trust Security**: Uses Argon2id for challenge-response authentication. Signaling server hardened against hijacking and ghost connections.
- **Config & Pairing**: 12-digit unique IDs and QR code pairing (including screenshot import).
- **Host CLI/TUI**: A dedicated `frankn-host config` TUI for managing settings with Vim keybindings.
- **Media Control**: Real-time sync of track info, album art, and volume. Control your PC's audio from your phone.
- **File System**: Recursive browsing, chunked binary transfers with SHA-256 validation, and a built-in code editor.
- **Notification Mirroring**: My PC's notifications show up on my phone in real-time via D-Bus integration.
- **Neural Chat (Dohee)**: Integrated AI assistant powered by local LLM inferencing. Direct `llama-server` management with persistent session history and high-speed token streaming.
- **Remote Trackpad**: High-performance pointer and scroll control with batched events and perfect Linux keycode mapping.

## Getting Started

### 1. Signaling Server
This is the matchmaker. Run it anywhere with a public IP.
```bash
cd frankn-signaling-server
cargo run --release
```

### 2. The Host
Run this on the machine you want to control. On first run, it will guide you through an interactive setup.
```bash
cd frankn-host
cargo run --release
```
To pair your phone, run:
```bash
frankn-host pair
```

### 3. The Client
Build the Flutter app, scan the QR code from the host, and you're in.
```bash
cd frankn
flutter pub get
flutter run
```

## Current Progress & End Goal

**Status:** Phase 5 (Advanced Features)
- [x] P2P WebRTC Transport & Auth (Argon2id)
- [x] Persistent Configuration Provider (TOML) with custom path support
- [x] Host CLI tool & TUI Config Editor (Vim binds)
- [x] QR Code & 12-digit ID Pairing (+ Screenshot Import)
- [x] System Control (Power, Processes, Logs)
- [x] Immersive Terminal & File Browser
- [x] Integrated file viewer & editor with syntax highlighting
- [x] Media Sync & Notification Mirroring
- [x] Neural Chat & Local LLM Integration
- [x] High-performance Remote Trackpad & Virtual Keyboard
- [ ] Bidirectional Folder Sync
- [ ] Mobile-as-Host (Control the phone from the PC)

**The End Goal:** A fully decentralized, low-latency ecosystem where I can manage my entire digital footprint from a single mobile interface, regardless of where I am or how bad my internet is.

---

### Contributions
I'm sharing this publicly because I think it's useful. While this is primarily a personal project, feel free to fork it, play around, and suggest improvements!

---
*Built with Rust and Flutter. Cyberpunk aesthetic intended.*