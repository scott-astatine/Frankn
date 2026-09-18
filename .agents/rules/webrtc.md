## WebRTC

Rules:
- This project uses **STUN only** for NAT traversal. **NEVER** suggest, recommend, or implement TURN relay servers. TURN is fundamentally against the design philosophy of this project — all connections are peer-to-peer via STUN/srflx candidates.
- Do not diagnose ICE failures as "needs TURN" — investigate the actual network conditions instead.
