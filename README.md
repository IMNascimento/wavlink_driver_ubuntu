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

- The **official installer aborts** on Ubuntu 24.04's kernel (6.8+): it ends with
  `Failed to install evdi ... to the kernel` / `bad exit status: 2`, rolls itself
  back, and the driver is never installed (`/opt/siliconmotion` is not created).
- After installing the driver, the desktop boots to a **frozen gray screen**; you
  can only get in through recovery mode.
- Plugging the USB display makes it flash ("universal graphic") and then go
  **black**, the desktop never appears on it.

## Root cause

Three problems, all in the open-source EVDI layer, none in the firmware. The first
strikes at install time; the other two strike on the desktop after installing.

0. **Installer aborts on modern kernels (build failure).** The vendor `.run`
   bundles **EVDI 1.14.7** (Nov 2024). Its DKMS build does not compile against
   kernel **6.8+** (the kernel internal DRM API changed), so the module build
   fails with `bad exit status: 2`, the installer auto-reverts, and nothing is
   installed. Fixed by swapping the bundled EVDI for **1.15.0** (Jul 2026), which
   builds cleanly on current kernels — see [Step 0](#step-0--make-the-official-driver-install-at-all).

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
- The **official Silicon Motion driver installed** under `/opt/siliconmotion`
  (this repo patches it, it does not replace it). On kernel **6.8+** the vendor
  installer will not complete on its own — do [Step 0](#step-0--make-the-official-driver-install-at-all)
  first. Get the driver from WAVLINK's download center and pick your SM768-based
  model (e.g. WL-UG7601HC / WL-UG7602HC):
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

## Step 0 — make the official driver install at all

Do this only if the official installer failed (kernel 6.8+). It leaves the vendor
package untouched and writes a patched copy next to it, with the bundled EVDI
1.14.7 replaced by 1.15.0 so the DKMS build succeeds.

```bash
# point it at the vendor installer (WAVLINK download, SMIUSBDisplay-driver.*.run)
./scripts/prepare-vendor-driver.sh --run "SMIUSBDisplay-driver.2.22.1.0.run"

# or at an already-extracted vendor folder:
./scripts/prepare-vendor-driver.sh --dir "SMIUSBDisplay"
```

It prints the path of the patched folder; install the vendor driver from there:

```bash
cd <folder-it-printed>          # e.g. SMIUSBDisplay-patched-evdi1.15.0
sudo ./install.sh               # now the EVDI build succeeds → Installation complete!
```

It runs **fully offline** — the EVDI 1.15.0 source is bundled in this repo
(`third_party/evdi-1.15.0.tar.gz`), so nothing is downloaded. The only file you
fetch yourself is the vendor driver, which is closed-source and cannot be
redistributed here.

Flags: `--evdi-src <dir|tarball>` to point at a different local EVDI source,
`--evdi-tag <tag>` to clone another release from GitHub instead of the bundle,
`--dry-run` to preview, `--help` for all options.

**Secure Boot:** no extra step. DKMS signs the EVDI module with the machine's
already-enrolled MOK key (`/var/lib/shim-signed/mok/MOK.der`) — the same key
Ubuntu uses for VirtualBox and other DKMS modules. You do not create or enroll a
new key. Confirm with `mokutil --sb-state`.

After the vendor driver installs cleanly, continue with the desktop fix below.

## Quick start

```bash
git clone https://github.com/IMNascimento/wavlink_driver_ubuntu.git
cd wavlink_driver_ubuntu

# 0. only if the official installer failed on kernel 6.8+ (see Step 0 above):
./scripts/prepare-vendor-driver.sh --run "SMIUSBDisplay-driver.2.22.1.0.run"

./scripts/diagnose.sh     # 1. read-only health check, changes nothing
sudo ./install.sh         # 2. apply the desktop fix
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
| `scripts/prepare-vendor-driver.sh` | Step 0: repacks the vendor `evdi.tar.gz` with EVDI 1.15.0 so the official installer builds on kernel 6.8+. |
| `third_party/evdi-1.15.0.tar.gz` | Bundled EVDI 1.15.0 source so Step 0 runs offline. |
| `patches/evdi-open-attached-to-null-guard.patch` | The one-line NULL guard for `evdi_open_attached_to()`. |
| `scripts/diagnose.sh` | Read-only system health check. |
| `install.sh` | Builds the patched libevdi from the vendor's `evdi.tar.gz`, backs up the original, installs it, disables the boot force-load, enables on-plug startup. |
| `uninstall.sh` | Reverts everything to the vendor-default state. |

## Troubleshooting

- **Official installer ends with `Failed to install evdi` / `bad exit status: 2`**:
  the bundled EVDI 1.14.7 does not build on kernel 6.8+. Run
  [Step 0](#step-0--make-the-official-driver-install-at-all)
  (`./scripts/prepare-vendor-driver.sh`) and install from the patched copy.
- **`$SMI_DIR not found`**: the official Silicon Motion driver is not installed
  yet; the vendor files must be in `/opt/siliconmotion`. If its installer aborts,
  see the entry above.
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
