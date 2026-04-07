# mt7610u_wifi_sta_v3002_dpo_20130916

## Modified Version for Ubuntu 18.04 / kernel 4.15

This repository contains a locally modified variant of the original driver source,
targeting the **TP-Link AC600 Archer T2UH** USB Wi-Fi adapter on Ubuntu 18.04
with kernel `4.15.0-213-generic`.

USB adapter: `148f:761a` (MediaTek MT7610U — used by the Archer T2UH).

The resulting module is `mt7650u_sta.ko`. The wireless interface appears as `ra0`.

---

## Quick Install

```bash
git clone <this-repo>
cd mt7610u_wifi_sta_v3002_dpo_20130916-Modified-usb-wifi-driver-for-TP_link-AC600-Archer-T2UH
sudo bash install.sh
```

---

## Manual Build and Install

Install build dependencies:

```bash
sudo apt install -y build-essential git linux-headers-$(uname -r)
```

Build the module:

```bash
make
```

Install:

```bash
sudo cp os/linux/mt7650u_sta.ko /lib/modules/$(uname -r)/kernel/drivers/net/wireless/
sudo depmod -a
sudo modprobe -r mt7650u_sta 2>/dev/null; sudo modprobe mt7650u_sta
```

Load automatically at boot:

```bash
echo mt7650u_sta | sudo tee /etc/modules-load.d/mt7650u_sta.conf
```

Verify:

```bash
dmesg | grep mt7650u
ip link show ra0
nmcli device status
```

Connect to a network:

```bash
nmcli device wifi list
nmcli device wifi connect "NETWORK_NAME" password "PASSWORD"
```

---

## Source Changes Applied

All changes relative to the upstream source:

| File | Change |
|------|--------|
| `os/linux/config.mk` | Disable CFG80211 — incompatible with kernel 4.15 APIs |
| `os/linux/sta_ioctl.c` | Fix `SIOCSIWPMKSA` handler: use `extra` instead of user-space `wrqu->data.pointer` (kernel oops fix); fix `siwfreq` and `giwap` error paths |
| `common/rtusb_io.c` | Fix missing return values in `write_reg` / `read_reg` |
| `mcu/mcu.c` | Fix missing return values and pointer increment in `MCURandomWrite` |
| `common/rtmp_init.c` | Fallback MAC `02:11:22:33:44:55` when EEPROM reports all-zeros |
| `os/linux/rt_linux.c` | Fallback MAC in `RtmpOSNetDevAddrSet` when address is all-zeros |
| `os/linux/rt_main_dev.c` | Pre-initialize `netDevHook.devAddr` with fallback MAC before netdev registration |

Notes:

- The interface is registered with the fallback MAC at probe time.
  Once the interface is opened, the real MAC is read from EEPROM and applied.
- The interface name is `ra0`, not `wlan0` or `wlp*`.
- CFG80211 is disabled. NetworkManager manages the interface via legacy wireless extensions.

---

## Earlier History

Modified for RaspberryPI2 kernel 4.1.7-v7+ armv7l GNU/Linux:
- `os/linux/rt_linux.c`: fix file operations

Modified for TP-Link TL-WDN5200 / Archer T2U:
- `common/rtusb_dev_id.c`: add product ID
- `include/os/rt_linux.h`, `os/linux/rt_linux.c`: fix compile errors, 64-bit fix
- `os/linux/config.mk`: Ubuntu defaults
