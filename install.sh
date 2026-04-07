#!/usr/bin/env bash
# install.sh — Build and install the mt7650u_sta driver
# Target: Ubuntu 18.04 / kernel 4.15.x
# Usage: sudo bash install.sh

set -e

KERNEL=$(uname -r)
MODULE=mt7650u_sta
KO=os/linux/${MODULE}.ko
DEST=/lib/modules/${KERNEL}/kernel/drivers/net/wireless/
AUTOLOAD=/etc/modules-load.d/${MODULE}.conf

# ── helpers ──────────────────────────────────────────────────────────────────

info()  { echo "[INFO]  $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

require_root() {
    [ "$(id -u)" -eq 0 ] || error "Run this script with sudo: sudo bash $0"
}

# ── steps ────────────────────────────────────────────────────────────────────

install_deps() {
    info "Installing build dependencies..."
    apt-get install -y build-essential git linux-headers-${KERNEL} 2>/dev/null \
        || error "apt-get failed. Are you online?"
}

build() {
    info "Cleaning previous build..."
    make clean

    info "Building module for kernel ${KERNEL}..."
    make || error "Build failed. Check output above."

    [ -f "${KO}" ] || error "Build succeeded but ${KO} not found."
    info "Build OK — ${KO}"
}

install_module() {
    info "Installing module to ${DEST}..."
    mkdir -p "${DEST}"
    cp "${KO}" "${DEST}${MODULE}.ko"
    depmod -a
    info "Module installed."
}

load_module() {
    info "Loading module..."
    if lsmod | grep -q "^${MODULE}"; then
        info "Module already loaded — reloading..."
        modprobe -r "${MODULE}" 2>/dev/null || true
    fi
    modprobe "${MODULE}" || error "modprobe failed. Check dmesg."
    info "Module loaded."
}

enable_autoload() {
    if [ ! -f "${AUTOLOAD}" ]; then
        echo "${MODULE}" > "${AUTOLOAD}"
        info "Autoload configured: ${AUTOLOAD}"
    else
        info "Autoload already configured: ${AUTOLOAD}"
    fi
}

verify() {
    info "Verifying..."

    sleep 1  # give the interface a moment to appear

    if ip link show ra0 &>/dev/null; then
        MAC=$(cat /sys/class/net/ra0/address 2>/dev/null || echo unknown)
        info "Interface ra0 is up — MAC: ${MAC}"
    else
        echo "[WARN]  Interface ra0 not found. Check: dmesg | grep mt7650u"
    fi

    echo ""
    echo "── dmesg (mt7650u) ──────────────────────────────────────────────"
    dmesg | grep mt7650u || true
    echo "─────────────────────────────────────────────────────────────────"
    echo ""
    echo "Run the following to connect to a Wi-Fi network:"
    echo "  nmcli device wifi list"
    echo "  nmcli device wifi connect \"NETWORK_NAME\" password \"PASSWORD\""
}

# ── main ─────────────────────────────────────────────────────────────────────

require_root
install_deps
build
install_module
load_module
enable_autoload
verify

info "Done."
