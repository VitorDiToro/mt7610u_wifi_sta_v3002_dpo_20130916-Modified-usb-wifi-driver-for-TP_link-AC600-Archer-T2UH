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
DAT_SRC=conf/RT2870STA.dat
DAT_DEST=/etc/Wireless/RT2870STA/RT2870STA.dat
CRDA_CONF=/etc/default/crda
SHUTDOWN_SVC=/etc/systemd/system/mt7650u-shutdown.service

# ── helpers ──────────────────────────────────────────────────────────────────

info()  { echo "[INFO]  $*"; }
warn()  { echo "[WARN]  $*"; }
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

install_config() {
    info "Installing driver configuration file..."

    [ -f "${DAT_SRC}" ] || error "Config file not found: ${DAT_SRC}. Is the repo complete?"

    mkdir -p "$(dirname ${DAT_DEST})"
    cp "${DAT_SRC}" "${DAT_DEST}"

    # Set CountryCode and CountryRegion for Brazil (channels 1-13)
    sed -i 's/^CountryCode=.*/CountryCode=BR/'    "${DAT_DEST}"
    sed -i 's/^CountryRegion=.*/CountryRegion=1/' "${DAT_DEST}"

    info "Config installed: ${DAT_DEST}"
}

configure_regulatory() {
    info "Configuring regulatory domain (BR)..."

    if [ -f "${CRDA_CONF}" ]; then
        # Update REGDOMAIN if already present, otherwise append
        if grep -q "^REGDOMAIN=" "${CRDA_CONF}"; then
            sed -i 's/^REGDOMAIN=.*/REGDOMAIN=BR/' "${CRDA_CONF}"
        else
            echo "REGDOMAIN=BR" >> "${CRDA_CONF}"
        fi
    else
        echo "REGDOMAIN=BR" > "${CRDA_CONF}"
    fi

    iw reg set BR 2>/dev/null || warn "iw reg set BR failed — crda may not be installed yet."
    service crda restart 2>/dev/null || true

    info "Regulatory domain set to BR (permanent)."
}

install_shutdown_service() {
    info "Installing shutdown service to prevent NetworkManager hang..."

    cat > "${SHUTDOWN_SVC}" <<'EOF'
[Unit]
Description=Cleanly unload mt7650u driver before network services stop
# After=X means: on shutdown our ExecStop runs BEFORE X stops.
# This ensures ra0 is down before NetworkManager, networking.service,
# and tailscaled attempt their own shutdown sequences.
DefaultDependencies=no
After=NetworkManager.service networking.service tailscaled.service basic.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStop=-/bin/ip link set ra0 down
ExecStop=-/sbin/modprobe -r mt7650u_sta
TimeoutStopSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable mt7650u-shutdown.service
    info "Shutdown service installed and enabled."
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

    sleep 2  # give the interface time to appear

    if ip link show ra0 &>/dev/null; then
        MAC=$(cat /sys/class/net/ra0/address 2>/dev/null || echo unknown)
        STATE=$(cat /sys/class/net/ra0/operstate 2>/dev/null || echo unknown)
        info "Interface ra0 found — MAC: ${MAC} | state: ${STATE}"

        if [ "${MAC}" = "02:11:22:33:44:55" ]; then
            warn "MAC address is the hardcoded fallback (02:11:22:33:44:55)."
            warn "The driver may still be failing to read the device EEPROM."
            warn "Check: dmesg | grep -E 'mt7650u|rt28xx|fail'"
        fi
    else
        warn "Interface ra0 not found. Check: dmesg | grep mt7650u"
    fi

    echo ""
    echo "── dmesg (mt7650u / rt28xx) ─────────────────────────────────────"
    dmesg | grep -E "mt7650u|rt28xx|RT2870|fail" || true
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
install_config          # copy RT2870STA.dat and set CountryCode=BR
configure_regulatory    # set REGDOMAIN=BR permanently
install_shutdown_service
load_module
enable_autoload
verify

info "Done."
