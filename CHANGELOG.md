# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [1.2.0] - 2026-07-23

### Added
- `scripts/set-virtual-displays.sh` — sets how many virtual displays the `evdi`
  module creates (`initial_device_count` in `/etc/modprobe.d/evdi.conf`). The
  vendor default of 4 is unchanged unless the user runs the script. Supports
  `--show` (no root), `--reset`, `--reload` to apply without replugging, and
  `--dry-run`; backs the original config up once to
  `/opt/siliconmotion/evdi-modprobe.conf.orig`.
- README (EN + PT-BR): a "Tuning the number of virtual displays" section covering
  what `initial_device_count` is, how many devices a given setup needs (a monitor
  on the machine's own HDMI/DP port is driven by the real GPU and consumes none),
  what lowering it does and does not save, why the vendor ships 4 (an upstream
  X.Org workaround that Wayland does not need), and why an undersized pool is
  safe (libevdi creates a card on demand via `/sys/devices/evdi/add`).

## [1.1.0] - 2026-07-23

### Added
- `scripts/prepare-vendor-driver.sh` — Step 0 helper that repacks the vendor
  `evdi.tar.gz` with EVDI 1.15.0 so the official Silicon Motion installer builds
  on kernel 6.8+. Supports `--run`/`--dir` inputs, `--evdi-src`, an `--evdi-tag`
  override, and `--dry-run`; never runs the vendor installer.
- `third_party/evdi-1.15.0.tar.gz` — bundled EVDI 1.15.0 source so Step 0 runs
  fully offline by default, with no download.
- README (EN + PT-BR): a "Step 0 — make the official driver install at all"
  section, a Secure Boot / MOK note (no key enrollment needed), and matching
  Symptoms, Root cause, How it works, and Troubleshooting entries.

### Fixed
- Official installer aborting on kernel 6.8+ (`Failed to install evdi`,
  `bad exit status: 2`): the bundled EVDI 1.14.7 does not compile against the
  current kernel DRM API; replacing it with EVDI 1.15.0 lets the vendor build,
  MOK-sign, and install succeed.

## [1.0.0] - 2026-07-22

### Added
- `patches/evdi-open-attached-to-null-guard.patch` — one-line NULL guard for
  `evdi_open_attached_to()` in libevdi 1.15.
- `scripts/diagnose.sh` — read-only system health check.
- `install.sh` — builds and installs the patched libevdi, disables the evdi boot
  force-load, and enables on-plug startup; includes `--build-only` and `--dry-run`
  test modes.
- `uninstall.sh` — reverts to the vendor-default driver state; includes `--dry-run`.
- Bilingual documentation: `README.md` (English) and `README.pt-BR.md` (Português).

### Fixed
- SM768 daemon SIGSEGV on monitor plug (`strlen(NULL)` in the deprecated
  `evdi_open_attached_to()` wrapper).
- Gray screen at boot on GNOME/Wayland caused by `evdi` being force-loaded at boot
  and racing GPU selection against `amdgpu`.
