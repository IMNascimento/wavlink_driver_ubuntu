# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

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
