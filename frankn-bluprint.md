# ⚡ Frankn: Master Edge Runtime Architecture & Technical Blueprint

> **Capabilities over applications.**  
> **Runtime before products.**  
> **Local before cloud.**  

This document serves as the master technical blueprint for **Frankn**, a modular, local-first runtime for distributed devices.

---

## 📜 1. Philosophy & Engineering Discipline

Frankn is built on the core principle of **Platform over Product**:

1. **Applications Solve Problems, Runtimes Enable Platforms:** Remote administration, inference engines, smart homes, and robotics are not hardcoded monolithic applications—they are composable capabilities running on top of a unified runtime.
2. **Engineering Discipline:** *Every new capability must justify its existence by making the runtime more reusable, not just more feature-rich.*
3. **Intents Over Pixels:** Avoids heavy video streaming (VNC/RDP). Streams structured intents (binary chunks, system metrics, terminal strings, input events) across dedicated P2P WebRTC data channels.
4. **Zero-Trust & Local-First:** Argon2id challenge-response authentication, constant-time timing-attack mitigations (`subtle`), home directory sandboxing (`dirs::home_dir()`), and zero reliance on public cloud relays.

---

## 🏗️ 2. Layered System Architecture

```mermaid
flowchart TD
    subgraph PlatformApps ["PLATFORM APPLICATIONS"]
        A1[Remote Operations Center]
        A2[Smart Home Engine]
        A3[Automation Hub]
        A4[Robotics & Edge Nodes]
        A5[Local Inference Suite]
    end

    subgraph Capabilities ["CAPABILITY SYSTEM"]
        C1[Filesystem Transceiver]
        C2[Terminal SSH]
        C3[Media & Audio Sync]
        C4[Inference Services<br/>Speech / Vision / LLM]
        C5[Input HUD]
        C6[Matter / MQTT / BLE]
    end

    subgraph CoreRuntime ["CORE RUNTIME"]
        R1[Capability Registry & Loader]
        R2[Memory Service]
        R3[State Store & Sync]
        R4[Event Bus]
        R5[Scheduler]
        R6[Zero-Trust Security & Sandboxing]
        R7[P2P WebRTC Transport]
    end

    subgraph Nodes ["FRANKN NODES"]
        N1[Linux PC / Workstation]
        N2[Windows PC]
        N3[macOS]
        N4[Android Mobile]
        N5[Raspberry Pi / Embedded / Containers]
    end

    PlatformApps --> Capabilities
    Capabilities --> CoreRuntime
    CoreRuntime --> Nodes
```

---

## 📡 3. Event Bus, State Store & Memory Service Architecture

```mermaid
sequenceDiagram
    participant Sensor as Event Source (Sensor / System)
    participant Bus as Core Event Bus
    participant State as State Store & Memory Service
    participant Auto as Automation Engine
    participant Inf as Inference Service (Optional)
    participant Action as Action Driver (SSH/D-Bus)

    Sensor->>Bus: Publish Event (e.g. Host Locked)
    Bus->>State: Persist & Update Context State
    Bus->>Auto: Dispatch Event Trigger
    Auto->>Inf: Query Context (If Reasoning Required)
    Inf-->>Auto: Response / Action Plan
    Auto->>Bus: Publish Action Intent
    Bus->>Action: Execute Action Capability
```

---

## 🔀 4. Data Channels & Topology

```mermaid
flowchart LR
    Client[Flutter Client<br/>Mobile / Desktop] <-->|SDP / ICE Handshake| Signal[Rust Signaling Server]
    Client <==>|Encrypted WebRTC P2P DataChannels| Host[Rust Host Node<br/>System Daemon]
    Host <--> Registry[Capability Registry & Loader]
    Registry <--> Dev[Devices & Subsystems]
```

### Protocol Lane Isolation
* `frankn_cmd`: System diagnostics, process managers, D-Bus, and power states.
* `frankn_fs`: High-speed binary storage transfers with SHA-256 validation.
* `frankn_media`: MPRIS track synchronization, WirePlumber/PulseAudio volume controls, and seek scrubbers.
* `frankn_ssh`: Raw terminal bridge backed by sticky modifier key states and persistent background session restoration.
* `frankn_input`: Batched pointer movements, scroll metrics, and virtual key mapping.
* `dohee_x`: Real-time streaming thread connecting to host inference daemons (`llama-server`).

*Note: Additional protocol lanes can be introduced dynamically without modifying existing capabilities.*

---

## 🛠️ 5. Capability Discovery & Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Discover
    Discover --> Install
    Install --> Register
    Register --> Initialize
    Initialize --> ExposeServices
    ExposeServices --> ReceiveEvents
    ReceiveEvents --> Shutdown
    Shutdown --> Unload
    Unload --> [*]
```

---

## 💻 6. Current Implementation Details

### A. Rust Node Runtime (`frankn-host`)
* **Security & Sandboxing:** Constant-time Argon2id verifiers, ancestor-validated path sandboxing, and RAII resource teardown on link drop.
* **Linux Integrations:** Direct D-Bus bindings for systemd power management, loginctl sessions, Hyprlock background processes, and PulseAudio/WirePlumber audio controls.
* **Storage Engine:** Multi-threaded directory indexing, chunked binary transfers, and `notify`-backed directory monitoring.
* **Inference Subsystem:** Modular `LlmManager` orchestrating model selection, persistent session mapping (`chats.json`), and server-sent event streaming.

### B. Flutter Multi-Platform Client (`frankn`)
* **Native Vector Diagram Engine (`neo_mermaid_widget.dart`)**: Pure Dart Mermaid flowchart parser and vector renderer with full-screen interactive zoom/pan modal (**zero Webview dependency**, 100% Linux Desktop compatible).
* **System File Intent Handler (`ACTION_VIEW`)**: Native file opener on Android routing `.md`, `.txt`, `.json`, `.py`, `.rs`, `.dart` files directly to viewer/editor screens.
* **Persistent SSH Session Restoration**: Back navigation keeps the active SSH WebRTC tunnel and terminal buffer alive in memory for instant re-attachment; explicit exit button tears down the shell.
* **Precision HUD Trackpad**: Touch gestures including 1-finger drags, 3-finger middle clicks, and sticky/locked modifier key states (`CTRL`, `ALT`, `SHIFT`).

---

## 🗺️ 7. Master Architectural Roadmap

```mermaid
timeline
    title Frankn Master Roadmap
    Phase 1 : Core Runtime [COMPLETE] : WebRTC P2P Transport : Argon2id Auth : Directory Sandboxing
    Phase 2 : Remote Operations [COMPLETE] : Systemctl & Process Managers : Interactive Terminal SSH : Precision HUD Trackpad
    Phase 3 : Storage & Media [COMPLETE] : High-Speed Binary Transceivers : Native Vector Mermaid Engine : Media Sync & Seek Scrubbing
    Phase 4 : Inference Runtime [IN PROGRESS] : Isolated dohee_x Streaming Lane : Model Selector : Rust Inference Sidecar
    Phase 5 : Automation Engine [PLANNED] : Event-Driven Pub/Sub Engine : Workflow Rules
    Phase 6 : Developer SDK [PLANNED] : Plugin ABI & Capability Registry : Developer Tooling
    Phase 7 : IoT Runtime [PLANNED] : Native Matter & MQTT Bridging : BLE Device Discovery
    Phase 8 : Multi-Node Clustering [FUTURE] : P2P Node Mesh Discovery : Distributed State Sync
    Phase 9 : Robotics Platform [FUTURE] : ROS Bridge : Hardware & Sensor Streaming
```

---

*Master Technical Blueprint — Last Updated: July 2026*
