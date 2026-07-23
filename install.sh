#!/usr/bin/env bash
#
# install.sh — build the patched libevdi and enable the SM768 USB display
#              on Ubuntu 24.04 (GNOME/Wayland), driven on-plug by udev.
#
# Run diagnose.sh first. This script only touches the open-source EVDI layer;
# it never modifies the closed-source Silicon Motion daemon or firmware.
#
# Modes:
#   sudo ./install.sh              apply the fix
#   ./install.sh --build-only      build the patched lib to a temp dir and
#                                  verify it compiles — installs nothing (no sudo)
#   ./install.sh --dry-run         print every action, change nothing
#   ./install.sh --help
#
set -euo pipefail

SMI_DIR="/opt/siliconmotion"
EVDI_SRC="$SMI_DIR/evdi.tar.gz"
PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/patches/evdi-open-attached-to-null-guard.patch"
BOOT_LOAD="/etc/modules-load.d/evdi.conf"
MODE="install"

for arg in "$@"; do
  case "$arg" in
    --dry-run)    MODE="dry-run" ;;
    --build-only) MODE="build-only" ;;
    -h|--help)    grep '^#' "$0" | grep -v '^#!' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)"; exit 2 ;;
  esac
done

if [ -t 1 ]; then BOLD=$'\e[1m'; GRN=$'\e[32m'; RED=$'\e[31m'; RST=$'\e[0m'; else BOLD=""; GRN=""; RED=""; RST=""; fi
say()  { printf '%s==>%s %s\n' "$GRN" "$RST" "$1"; }
die()  { printf '%serror:%s %s\n' "$RED" "$RST" "$1" >&2; exit 1; }
run()  { if [ "$MODE" = "dry-run" ]; then printf '  [dry-run] %s\n' "$*"; else eval "$*"; fi; }

# ---- preflight -------------------------------------------------------------
[ -f "$PATCH" ]     || die "patch not found: $PATCH"
[ -d "$SMI_DIR" ]   || die "$SMI_DIR not found — install the official Silicon Motion driver first."
if [ ! -f "$EVDI_SRC" ]; then
  [ -f "./evdi.tar.gz" ] && EVDI_SRC="./evdi.tar.gz" || die "EVDI source not found ($SMI_DIR/evdi.tar.gz)."
fi
for t in gcc make pkg-config patch tar; do command -v "$t" >/dev/null 2>&1 || die "missing build tool: $t (apt install build-essential pkg-config patch)"; done
pkg-config --exists libdrm 2>/dev/null || die "libdrm dev headers missing (apt install libdrm-dev)."

# ---- build the patched library into a temp dir -----------------------------
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
build_lib() {
  say "Extracting EVDI source from $EVDI_SRC"
  tar xzf "$EVDI_SRC" -C "$WORK"
  local root; root="$(dirname "$(find "$WORK" -type d -name library | head -n1)")"
  [ -n "$root" ] && [ -d "$root/library" ] || die "could not locate library/ in the EVDI source."
  say "Applying null-guard patch"
  patch -p1 -d "$root" < "$PATCH" >/dev/null || die "patch failed to apply — libevdi version may differ."
  grep -q 'strlen(sysfs_parent_device) : 0' "$root/library/evdi_lib.c" || die "patch verification failed."
  say "Building libevdi (make DEPS=)"
  make -C "$root/library" DEPS= >/dev/null 2>&1 || die "build failed — check gcc/libdrm-dev."
  BUILT="$root/library/libevdi.so.1.15.0"
  [ -f "$BUILT" ] || die "build produced no libevdi.so.1.15.0."
  say "Built: $BUILT"
}

if [ "$MODE" = "build-only" ]; then
  build_lib
  printf '\n%sBuild OK. The patched libevdi compiled cleanly. Nothing was installed.%s\n' "$BOLD" "$RST"
  printf 'Run %ssudo ./install.sh%s to apply it.\n' "$BOLD" "$RST"
  exit 0
fi

# ---- install / dry-run -----------------------------------------------------
if [ "$MODE" = "install" ] && [ "$(id -u)" -ne 0 ]; then
  die "installation needs root — run: sudo ./install.sh (or use --dry-run / --build-only)"
fi

[ "$MODE" = "dry-run" ] || build_lib

say "Backing up the original libevdi (once)"
if [ ! -f "$SMI_DIR/libevdi.so.orig" ] && [ -f "$SMI_DIR/libevdi.so" ]; then
  run "cp -a '$SMI_DIR/libevdi.so' '$SMI_DIR/libevdi.so.orig'"
else
  echo "  backup already present or no lib to back up — skipping."
fi

say "Installing the patched libevdi to $SMI_DIR/libevdi.so"
run "install -m 755 '${BUILT:-<built-lib>}' '$SMI_DIR/libevdi.so'"
run "ln -sf '$SMI_DIR/libevdi.so' /usr/lib/libevdi.so.1"
run "ln -sf '$SMI_DIR/libevdi.so' /usr/lib/libevdi.so.0"
run "ldconfig"

say "Disabling evdi boot force-load (prevents the gray screen)"
if [ -f "$BOOT_LOAD" ]; then
  run "mv '$BOOT_LOAD' '$SMI_DIR/modules-load-evdi.conf.disabled'"
else
  echo "  $BOOT_LOAD not present — nothing to disable."
fi

say "Enabling on-plug startup via udev"
run "systemctl unmask smiusbdisplay.service"
run "systemctl daemon-reload"
run "udevadm control --reload-rules"

if [ "$MODE" = "dry-run" ]; then
  printf '\n%sDry run complete. No changes were made.%s\n' "$BOLD" "$RST"
else
  printf '\n%sDone.%s Plug in the USB display — it should light up automatically.\n' "$BOLD" "$RST"
  printf 'To undo everything: %ssudo ./uninstall.sh%s\n' "$BOLD" "$RST"
fi
