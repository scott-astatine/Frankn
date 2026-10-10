# Signaling Server

The signaling server accepts TLS WebSocket connections only. Set `FRANKN_TLS_CERT` and `FRANKN_TLS_KEY` to PEM certificate and private-key paths before starting it. `FRANKN_SIGNALING_BIND` optionally sets the listen address; it defaults to `0.0.0.0:8037`. The certificate must be valid for the hostname clients use in their `wss://` URL.

For the systemd unit, create `/etc/frankn/signaling.env` with those variables and restrict the file so only the service administrator can read the private key path configuration. The process needs read access to the certificate and private key files.

Private Hosts begin with an empty allowlist, which denies normal client signaling and discovery. Scanning a Host QR code saves that Host in the client app and enables the one-time pairing flow. After the client proves the Host passcode, the Host persists that client's cryptographic peer ID to `allowed_clients` and publishes the updated ACL. Public Hosts remain reachable by all clients.
