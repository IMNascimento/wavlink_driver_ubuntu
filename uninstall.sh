#!/usr/bin/env bash
#
# uninstall.sh — revert everything install.sh did and return the driver to the
#                state it was in right after the official Silicon Motion install.
#
# This restores the original (unpatched) libevdi and the evdi boot force-load.
# WARNING: restoring the boot force-load can bring back the original gray-screen
# bug on Wayland. If that happens, just mask the service:
#     sudo systemctl mask smiusbdisplay.service
#
#   sudo ./uninstall.sh            revert
#   ./uninstall.sh --dry-run       print every action, change nothing
#   ./uninstall.sh --help
#
set -euo pipefail

SMI_DIR="/opt/siliconmotion"
BOOT_LOAD="/etc/modules-load.d/evdi.conf"
DISABLED="$SMI_DIR/modules-load-evdi.conf.disabled"
MODE="revert"

for arg in "$@"; do
  case "$arg" in
    --dry-run) MODE="dry-run" ;;
    -h|--help) grep '^#' "$0" | grep -v '^#!' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)"; exit 2 ;;
  esac
done

if [ -t 1 ]; then BOLD=$'\e[1m'; GRN=$'\e[32m'; RED=$'\e[31m'; RST=$'\e[0m'; else BOLD=""; GRN=""; RED=""; RST=""; fi
say() { printf '%s==>%s %s\n' "$GRN" "$RST" "$1"; }
die() { printf '%serror:%s %s\n' "$RED" "$RST" "$1" >&2; exit 1; }
run() { if [ "$MODE" = "dry-run" ]; then printf '  [dry-run] %s\n' "$*"; else eval "$*"; fi; }

[ -d "$SMI_DIR" ] || die "$SMI_DIR not found — nothing to revert."
if [ "$MODE" = "revert" ] && [ "$(id -u)" -ne 0 ]; then
  die "revert needs root — run: sudo ./uninstall.sh (or --dry-run)"
fi

say "Restoring the original libevdi"
if [ -f "$SMI_DIR/libevdi.so.orig" ]; then
  run "cp -a '$SMI_DIR/libevdi.so.orig' '$SMI_DIR/libevdi.so'"
  run "ldconfig"
else
  echo "  no libevdi.so.orig backup found — the library was never patched by us."
fi

say "Restoring the evdi boot force-load"
if [ -f "$DISABLED" ]; then
  run "mv '$DISABLED' '$BOOT_LOAD'"
else
  echo "  no disabled boot-load backup found — leaving boot config as-is."
fi

say "Reloading systemd and udev"
run "systemctl daemon-reload"
run "udevadm control --reload-rules"

if [ "$MODE" = "dry-run" ]; then
  printf '\n%sDry run complete. No changes were made.%s\n' "$BOLD" "$RST"
else
  printf '\n%sReverted to the vendor-default driver state.%s\n' "$BOLD" "$RST"
  printf 'If the gray screen returns on boot: %ssudo systemctl mask smiusbdisplay.service%s\n' "$BOLD" "$RST"
fi
