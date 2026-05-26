# ⚡ FRANKN // Remote Operations Center

Frankn is a decentralized, personal Remote Operations Center designed for secure, low-latency, peer-to-peer management of servers and personal workstations. Built on the core philosophy of **"Intents over Pixels"**, it prioritizes streaming structured system metadata, command payloads, and binary file chunks over heavy, bandwidth-hogging video buffers. 

---

## 🏗️ Architecture & WebRTC Protocol Lanes

The system establishes direct, end-to-end encrypted WebRTC P2P connections between your devices, bypassing public cloud relays, virtual private networks, or complex port forwarding. Initial discovery and handshake exchanges (SDP/ICE) are handled by a lightweight, self-hosted Signaling middleman.

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

Once paired, communication is multiplexed across specialized, high-performance WebRTC Data Channels:

| Data Channel | Operation | Description |
| :--- | :--- | :--- |
| `frankn_cmd` | System Control | Handles process diagnostics, systemd power states, and command dispatching. |
| `frankn_fs` | Binary Storage | Manages chunked, high-speed file transceivers with SHA-256 integrity validation. |
| `frankn_media` | Media Telemetry | Bidirectional audio mixer tracking, album art synchronization, and stream scrubbing. |
| `frankn_ssh` | Terminal Bridge | Establishes a raw xterm SSH bridge with Nerd Font support and session restoration. |
| `frankn_input` | Remote Input | Batches precise Pointer movements, scroll metrics, and virtual keypresses. |
| `dohee_x` | Neural Chat | Secure, isolated local LLM streaming thread connecting to the host `llama-server`. |

---

## 📸 Cyberpunk User Interface

<div align="center">
  <img src="frankn/docs/dohee_dashboard.png" width="15%" />
  <img src="frankn/docs/ssh_screen.png" width="15%" />
  <img src="frankn/docs/client_logs.png" width="15%" />
  <img src="frankn/docs/file_browser.png" width="15%" />
  <img src="frankn/docs/process_manager.png" width="15%" />
  <img src="frankn/docs/sync_manager.png" width="15%" />
</div>

<br>

<details>
<summary><b>👀 View more system interface telemetry</b></summary>
<br>
<div align="center">
  <img src="frankn/docs/dohee_chat_latex.png" width="24%" />
  <img src="frankn/docs/dohee_chat_latex2.png" width="24%" />
  <img src="frankn/docs/trackpad_screen.png" width="24%" />
  <img src="frankn/docs/sys_log.png" width="24%" />
  <img src="frankn/docs/systray.png" width="24%" />
  <img src="frankn/docs/proc2.png" width="24%" />
  <img src="frankn/docs/dohee_x.png" width="24%" />
  <img src="frankn/docs/auth_dialog.png" width="24%" />
  <img src="frankn/docs/host_list_saved.png" width="24%" />
  <img src="frankn/docs/host_list_empty.png" width="24%" />
  <img src="frankn/docs/ssh_auth.png" width="24%" />
  <img src="frankn/docs/config_screen.png" width="24%" />
  <img src="frankn/docs/sync_pair_dialog.png" width="24%" />
</div>
</details>

---

## 🦸‍♂️ Capabilities & Core Features

### 🔐 Zero-Trust Cryptographic Security
* **Constant-Time Argon2id Auth:** Hardened challenge-response pairing protocol utilizing `subtle` verifiers to mitigate timing side-channel attacks.
* **Home Directory Sandboxing:** Enforces strict local directory barriers (`dirs::home_dir()`), recursively walking path structures to completely prevent parent directory traversal escapes.
* **RAII Resource Management:** Connection handshakes automatically purge active file descriptors and memory-held signaling bindings upon link drop.

### 📁 Advanced Files Orchestration
* **Android Storage API Bypass:** Integrated a custom pure-Dart directory traversal engine listing folders asynchronously in sub-milliseconds to avoid native Storage Access Framework Tree crashes.
* **Custom Landing Directories:** Supports persistent download landing configurations alongside dynamic, on-demand routing controls to choose custom storage targets for individual transfers.
* **Frosted Glassmorphic Context Sheets:** File items display responsive telemetry diagnostics (size, type, and subsystem origin) inside custom frosted blurs with icon-guided operations.
* **High-Speed Transfer Throttling:** Restricts Native progress redraws to a strict 2Hz limit, keeping the client completely fluid and responsive during gigabit-level P2P transfers.

### 🎬 Media Synchronization
* **Real-time State & Seek Sync:** Bidirectional streaming of workstation volume mixers (WirePlumber/PulseAudio), track details, and album art with gesture-based track seeking.

### 🖥️ Precise Workstation Inputs
* **Precision HUD Trackpad:** Supports 1-finger long-press drag gestures, 3-finger middle-click taps, and dual-state modifier key locking (Ctrl, Alt, Shift, Super) mapped directly to host `uinput` Linux virtual keys.
* **Terminal Shell & Session Restoration:** Persistent terminal sessions over WebRTC with sticky modifiers and in-memory SSH credential caching for seamless reconnections.

---

## 🚀 Getting Started

### 1. Matchmaker (Signaling)
Run this lightweight middleman on a VPS or public IP to facilitate the WebRTC handshakes:
```bash
cd frankn-signaling-server
cargo run --release
```

### 2. Workstation Host
Run this on the machine you want to command. First-time startup launches an interactive configurator.
```bash
cd frankn-host
./install.sh
```
To pair your client, launch the interactive QR code generator:
```bash
frankn-host pair
```

### 3. Mobile Client
Compile the Flutter engine and connect to your hosts:
```bash
cd frankn
flutter pub get
flutter run
```

---

## 🗺️ Progress Checklist & Project Path

**Current Phase:** Phase 5 (Advanced Protocols Integration)
- [x] WebRTC End-to-End Encrypted Transport & Argon2id Verifications
- [x] Host Configuration Provider (TOML) with custom path selectors (`-c` flags)
- [x] Workstation Configuration TUI & Vim-based binds
- [x] Secure QR Code Handshakes, 12-digit Unique IDs, & Screenshot Import
- [x] Workstation Control Nodes (Systemctl, D-Bus, Hyprlock, Process managers)
- [x] Immersive Terminal Emulator & Synced Viewer
- [x] Frosted Glassmorphism Context UI & Neon Sorting Panels
- [x] Bidirectional Storage Synchronizations (Sequenced batch folder mirroring)
- [x] Precise Virtual Remote Pointer & Multi-touch gestures
- [ ] Neural Chat & Local LLM Chat Thread (`LlmManager` streaming & persistence)
- [ ] Mobile-as-Host Protocol (Reverse controller logic)

---

*Built with Rust and Flutter. Cyberpunk aesthetic intended.*
