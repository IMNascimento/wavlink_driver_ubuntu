# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [1.1.0] - 2026-07-23

### Added
- `scripts/prepare-vendor-driver.sh` — Step 0 helper that repacks the vendor
  `evdi.tar.gz` with EVDI 1.15.0 so the official Silicon Motion installer builds
  on kernel 6.8+. Supports `--run`/`--dir` inputs, offline `--evdi-src`, an
  `--evdi-tag` override, and `--dry-run`; never runs the vendor installer.
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
