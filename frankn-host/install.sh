#!/bin/bash

# Frankn Host Installer (User Service, Global Binary)
set -e

# Ensure we are NOT running the whole script as root
if [ "$EUID" -eq 0 ]; then
  echo "ERROR: Please run this script as your normal user, NOT as root."
  echo "You will be prompted for your sudo password when copying the binary to /usr/bin."
  exit 1
fi

echo "Building Frankn Host binary (Release Mode)..."
cd "$(dirname "$0")"
cargo build --release

echo "Stripping binary..."
strip target/release/frankn-host

systemctl --user stop frankn-host

echo "Installing binary globally to /usr/bin/frankn-host (requires sudo)..."
sudo cp target/release/frankn-host /usr/bin/frankn-host

# Ensure user systemd directory exists
mkdir -p "$HOME/.config/systemd/user"

echo "Installing user systemd service..."
cp ../frankn-host.service "$HOME/.config/systemd/user/frankn-host.service"

echo "Reloading user systemd daemon..."
systemctl --user daemon-reload
systemctl --user enable frankn-host
systemctl --user restart frankn-host

echo ""
echo "✅ Frankn Host installed and started successfully!"
echo "The configuration file will be stored in: $HOME/.config/frankn/config.toml"
echo ""
echo "You can check the status of the service at any time by running:"
echo "  systemctl --user status frankn-host"
echo "And view the live logs by running:"
echo "  journalctl --user -u frankn-host -f"
