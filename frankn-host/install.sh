#!/bin/bash

# Frankn Host Installer (User Service, Global Binary)
set -e

# Ensure we are NOT running the whole script as root
if [ "$EUID" -eq 0 ]; then
  echo "ERROR: Please run this script as your normal user, NOT as root."
  echo "You will be prompted for your sudo password when copying the binary to /usr/bin."
  exit 1
fi

setup_uinput() {
  local install_user
  local install_group

  install_user="$(id -un)"
  install_group="$(id -gn)"

  echo "Configuring uinput for Frankn remote input..."

  # Load the kernel module now and automatically on future boots.
  printf 'uinput\n' | sudo tee /etc/modules-load.d/frankn-uinput.conf >/dev/null

  # Frankn runs as a user service. Limit /dev/uinput access to that user's
  # primary group instead of making the device world-writable.
  printf 'KERNEL=="uinput", MODE="0660", GROUP="%s"\n' "$install_group" \
    | sudo tee /etc/udev/rules.d/60-frankn-uinput.rules >/dev/null

  sudo udevadm control --reload-rules
  sudo modprobe uinput
  sudo udevadm trigger --action=change --name-match=/dev/uinput
  sudo udevadm settle

  # A user service starts at boot only when lingering is enabled.
  if ! sudo loginctl enable-linger "$install_user"; then
    echo "WARNING: Could not enable user-service lingering for $install_user."
    echo "         frankn-host will still start when the user logs in."
  fi

  if [ ! -r /dev/uinput ] || [ ! -w /dev/uinput ]; then
    echo "WARNING: $install_user cannot access /dev/uinput yet."
    echo "         Reboot or log out and back in, then restart frankn-host."
  fi
}

echo "Building Frankn Host binary (Release Mode)..."
cd "$(dirname "$0")"
cargo build --release

echo "Stripping binary..."
strip target/release/frankn-host

systemctl --user stop frankn-host 2>/dev/null || true

setup_uinput

echo "Installing binary globally to /usr/bin/frankn-host (requires sudo)..."
sudo cp target/release/frankn-host /usr/bin/frankn-host

# Ensure user systemd directory exists
mkdir -p "$HOME/.config/systemd/user"

echo "Installing user systemd service..."
cp ./frankn-host.service "$HOME/.config/systemd/user/frankn-host.service"

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
