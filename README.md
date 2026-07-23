# WAVLINK / SM768 USB Display Fix for Ubuntu 24.04

![License](https://img.shields.io/badge/license-GPLv3-blue.svg)
![Platform](https://img.shields.io/badge/platform-Ubuntu%2024.04-orange)
![Session](https://img.shields.io/badge/session-Wayland%20%7C%20X11-informational)

**English** · [Português](README.pt-BR.md)

Makes WAVLINK / Silicon Motion **SM768** USB display adapters (USB id `090c:0768`)
work on **Ubuntu 24.04** with **GNOME/Wayland**, the setup where the official
Silicon Motion driver leaves you with a **gray screen at boot** and a USB monitor
that **lights up and goes black** when plugged in.

The fix lives entirely in the open-source (GPL) EVDI layer. It never touches the
closed-source Silicon Motion daemon or firmware.

---

## Symptoms this fixes

- After installing the official driver, the desktop boots to a **frozen gray
  screen**; you can only get in through recovery mode.
- Plugging the USB display makes it flash ("universal graphic") and then go
  **black**, the desktop never appears on it.

## Root cause

Two independent bugs, both in the open EVDI layer, not in the firmware:

1. **Daemon crash on plug (`SIGSEGV`).** When a monitor is plugged in, the
   `SMIUSBDisplayManager` daemon calls the deprecated `evdi_open_attached_to(NULL)`
   to get a generic EVDI device. In libevdi **1.15** that wrapper runs
   `strlen(NULL)` before `evdi_open_attached_to_fixed()`, which actually handles
   `NULL` correctly, ever gets the pointer. The result is a null-pointer
   dereference that kills the daemon every single time a display is connected.

2. **Gray screen at boot (GPU selection).** The official installer drops
   `/etc/modules-load.d/evdi.conf`, which **force-loads the `evdi` module at every
   boot** with four virtual displays. Those virtual cards join the init race just
   as `amdgpu` is coming up, and `mutter` (Wayland) sometimes picks the EFI boot
   framebuffer (`simpledrm`) as the primary GPU, fails to render
   (`gbm_surface_lock_front_buffer failed`), and shows a gray screen.

The fix is a one-line NULL guard in `library/evdi_lib.c` (rebuilt into libevdi)
plus stopping `evdi` from loading at boot. It then loads on demand when you plug
the display, after the display manager is already up.

## Requirements

- Ubuntu 24.04 (also expected to work on 23.04 / 22.04 / 20.04).
- The **official Silicon Motion driver already installed** (this repo patches it,
  it does not replace it). The vendor files must be under `/opt/siliconmotion`.
  Get the driver from WAVLINK's download center and pick your SM768-based model
  (e.g. WL-UG7601HC / WL-UG7602HC):
  <https://www.wavlink.com/en_us/drivers.html>
- Build tools: `build-essential pkg-config patch libdrm-dev`.

```bash
sudo apt install build-essential pkg-config patch libdrm-dev
```

## Environment we tested on

| Component | Version |
| --- | --- |
| Distribution | Ubuntu 24.04.4 LTS (Noble Numbat) |
| Kernel | 6.17.0-35-generic |
| Desktop | GNOME Shell 46.0 |
| Display server / interface | **Wayland** (also works on X11) |
| Login manager | GDM3 |
| GPU driver | AMD `amdgpu` (Lucienne APU) |
| EVDI / libevdi | 1.15.0 |
| USB adapter | WAVLINK WL-UG7602HC (Silicon Motion SM768), `090c:0768` |
| External display | 1920x1080 @ 60 Hz |

## Quick start

```bash
git clone https://github.com/IMNascimento/wavlink_driver_ubuntu.git
cd wavlink_driver_ubuntu

./scripts/diagnose.sh     # 1. read-only health check, changes nothing
sudo ./install.sh         # 2. apply the fix
# 3. plug in the USB display, it should light up automatically
```

## Test before you commit to anything

Three layers of safe checking, none of which modify your system permanently:

| Command | What it does | Root? |
| --- | --- | --- |
| `./scripts/diagnose.sh` | Reports OS, GPU, adapter, fix status, deps. Read-only. | no |
| `./install.sh --build-only` | Compiles the patched libevdi to a temp dir and verifies it. Installs nothing. | no |
| `./install.sh --dry-run` | Prints every action it *would* take. Changes nothing. | no |

Run all three and read the output before running the real `sudo ./install.sh`.

## Usage

Once installed, the display is fully automatic:

- **Plug in** the USB adapter → the service starts on-demand (via the vendor udev
  rule), `evdi` loads, and your desktop extends onto the external monitor.
- **Unplug** → the service stops. Nothing runs at boot, so boots stay clean.

Configure the external monitor (mirror / extend / resolution) in
**Settings → Displays** as usual.

## Reverting

Full revert to the vendor-default state:

```bash
sudo ./uninstall.sh        # add --dry-run to preview
```

This restores the original libevdi and the boot config. Note that restoring the
vendor boot config can bring back the original gray screen; if it does, just
neutralize the service:

```bash
sudo systemctl mask smiusbdisplay.service
```

## How it works

| File | Role |
| --- | --- |
| `patches/evdi-open-attached-to-null-guard.patch` | The one-line NULL guard for `evdi_open_attached_to()`. |
| `scripts/diagnose.sh` | Read-only system health check. |
| `install.sh` | Builds the patched libevdi from the vendor's `evdi.tar.gz`, backs up the original, installs it, disables the boot force-load, enables on-plug startup. |
| `uninstall.sh` | Reverts everything to the vendor-default state. |

## Troubleshooting

- **`$SMI_DIR not found`**: install the official Silicon Motion driver first;
  the vendor files must be in `/opt/siliconmotion`.
- **`patch failed to apply`**: your libevdi version differs from 1.15; the guard
  targets that release.
- **Still gray at boot**: confirm `/etc/modules-load.d/evdi.conf` is gone
  (`./scripts/diagnose.sh` reports this) and, as a last resort, mask the service.

## Credits & license

The patch modifies **libevdi**, which is licensed under the **GPL** by DisplayLink
(UK) Ltd. This repository is distributed under the **GPLv3** (see [LICENSE](LICENSE)).
The Silicon Motion binaries and firmware are **not** redistributed here; you need
the official driver installed (see [Requirements](#requirements) for the WAVLINK
download link).

See [Environment we tested on](#environment-we-tested-on) for exact versions.
