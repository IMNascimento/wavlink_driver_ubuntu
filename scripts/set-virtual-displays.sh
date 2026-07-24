#!/usr/bin/env bash
#
# set-virtual-displays.sh — choose how many virtual display devices (EVDI)
#     the driver creates.
#
# The vendor driver ships with 4 virtual outputs: it writes
# "options evdi initial_device_count=4" to /etc/modprobe.d/evdi.conf. You need
# one virtual device per physical output on your USB adapter, no more. A
# monitor plugged straight into the machine's own HDMI/DisplayPort port does
# NOT consume one: it is driven by your real GPU and never goes through EVDI.
# So a two-output adapter plus a direct HDMI monitor needs 2, not 4, and the
# spare devices just sit there idle.
#
# Usage:
#   ./scripts/set-virtual-displays.sh --show        show the current setting
#   sudo ./scripts/set-virtual-displays.sh 2        create 2 virtual displays
#   sudo ./scripts/set-virtual-displays.sh --reset  restore the vendor default (4)
#     [--reload]    apply right now: stop the daemon, reload evdi, restart it
#     [--dry-run]   print every action, change nothing
#     [--help]
#
# Without --reload the new count takes effect the next time the evdi module
# loads, which is the next time you plug the adapter in. --show needs no root.
#
# This only edits the modprobe option for the open-source EVDI module. It never
# touches the closed-source Silicon Motion daemon or firmware.
#
set -euo pipefail

SMI_DIR="/opt/siliconmotion"
CONF="/etc/modprobe.d/evdi.conf"
BACKUP="$SMI_DIR/evdi-modprobe.conf.orig"
VENDOR_DEFAULT=4
MAX_DEVICES=16
COUNT=""
MODE="set"
RELOAD=""

if [ -t 1 ]; then BOLD=$'\e[1m'; DIM=$'\e[2m'; GRN=$'\e[32m'; RED=$'\e[31m'; YLW=$'\e[33m'; RST=$'\e[0m'; else BOLD=""; DIM=""; GRN=""; RED=""; YLW=""; RST=""; fi
say()  { printf '%s==>%s %s\n' "$GRN" "$RST" "$1"; }
warn() { printf '%swarning:%s %s\n' "$YLW" "$RST" "$1"; }
die()  { printf '%serror:%s %s\n' "$RED" "$RST" "$1" >&2; exit 1; }
run()  { if [ "$MODE" = "dry-run" ]; then printf '  [dry-run] %s\n' "$*"; else eval "$*"; fi; }

while [ $# -gt 0 ]; do
  case "$1" in
    --show)     MODE="show"; shift ;;
    --reset)    COUNT="$VENDOR_DEFAULT"; shift ;;
    --reload)   RELOAD="yes"; shift ;;
    --dry-run)  MODE="dry-run"; shift ;;
    -h|--help)  grep '^#' "$0" | grep -v '^#!' | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)         die "unknown option: $1 (try --help)" ;;
    *)          COUNT="$1"; shift ;;
  esac
done

# ---- helpers ---------------------------------------------------------------
configured_count() { # the value modprobe will use on the next load
  [ -f "$CONF" ] || return 1
  awk '/^[[:space:]]*options[[:space:]]+evdi/ {
         for (i = 1; i <= NF; i++)
           if ($i ~ /^initial_device_count=/) { sub(/^initial_device_count=/, "", $i); v = $i }
       } END { if (v != "") print v }' "$CONF"
}

live_evdi_cards() { # how many DRM cards the evdi driver owns right now
  local n=0 d
  for d in /sys/class/drm/card[0-9]*/device/driver; do
    [ -e "$d" ] || continue
    [ "$(basename "$(readlink -f "$d")")" = "evdi" ] && n=$((n + 1))
  done
  printf '%s\n' "$n"
}

show_state() {
  local cfg live
  cfg="$(configured_count || true)"
  printf '\n%sVirtual displays (EVDI)%s\n' "$BOLD" "$RST"
  if [ -n "$cfg" ]; then
    printf '  configured : %s%s%s   %s(%s)%s\n' "$BOLD" "$cfg" "$RST" "$DIM" "$CONF" "$RST"
  elif [ -f "$CONF" ]; then
    printf '  configured : %s(no initial_device_count in %s — module default applies)%s\n' "$DIM" "$CONF" "$RST"
  else
    printf '  configured : %s(no %s — module default applies)%s\n' "$DIM" "$CONF" "$RST"
  fi
  if [ -r /sys/module/evdi/parameters/initial_device_count ]; then
    live="$(live_evdi_cards)"
    printf '  loaded now : %s, %s DRM card(s) in /dev/dri\n' \
      "$(cat /sys/module/evdi/parameters/initial_device_count)" "$live"
  else
    printf '  loaded now : %sevdi not loaded (adapter unplugged) — this is normal%s\n' "$DIM" "$RST"
  fi
  printf '\n  %sRemember:%s a monitor on the machine own HDMI/DP port does not use\n' "$DIM" "$RST"
  printf '  a virtual display. Count only the outputs on the USB adapter.\n\n'
}

if [ "$MODE" = "show" ]; then
  show_state
  exit 0
fi

# ---- validate --------------------------------------------------------------
[ -n "$COUNT" ] || die "give a number of virtual displays, e.g. 'sudo $0 2' (try --help)."
case "$COUNT" in
  ''|*[!0-9]*) die "'$COUNT' is not a whole number." ;;
esac
COUNT=$((10#$COUNT))
[ "$COUNT" -ge 1 ] || die "at least 1 virtual display is required."
[ "$COUNT" -le "$MAX_DEVICES" ] || die "evdi supports at most $MAX_DEVICES devices."

[ -d "$SMI_DIR" ] || die "$SMI_DIR not found — install the official Silicon Motion driver first."
if [ "$MODE" = "set" ] && [ "$(id -u)" -ne 0 ]; then
  die "changing the count needs root — run: sudo $0 $COUNT (or use --dry-run / --show)"
fi

CURRENT="$(configured_count || true)"
if [ "$CURRENT" = "$COUNT" ]; then
  say "Already set to $COUNT virtual display(s) — nothing to change."
  if [ -z "$RELOAD" ]; then
    show_state
    exit 0
  fi
fi

# ---- write the config ------------------------------------------------------
if [ ! -f "$BACKUP" ] && [ -f "$CONF" ]; then
  say "Backing up the original modprobe config (once) to $BACKUP"
  run "cp -a '$CONF' '$BACKUP'"
fi

say "Setting initial_device_count=$COUNT in $CONF"
run "printf 'options evdi initial_device_count=%s\n' '$COUNT' > '$CONF'"
run "chmod 644 '$CONF'"

# ---- apply now, or on the next plug ----------------------------------------
if [ -n "$RELOAD" ]; then
  if [ ! -d /sys/module/evdi ]; then
    say "evdi is not loaded — nothing to reload, the new count applies on the next plug."
  else
    warn "Reloading evdi drops every virtual display. Any window on the USB screen moves back to the built-in one."
    say "Stopping the display daemon and reloading evdi"
    run "systemctl stop smiusbdisplay.service || true"
    run "sleep 1"
    run "modprobe -r evdi" || die "could not unload evdi — unplug the adapter and try again, or just replug it to apply."
    run "modprobe evdi"
    run "systemctl start smiusbdisplay.service || true"
    say "Reloaded."
  fi
fi

if [ "$MODE" = "dry-run" ]; then
  printf '\n%sDry run complete. No changes were made.%s\n' "$BOLD" "$RST"
else
  show_state
  if [ -z "$RELOAD" ]; then
    printf '%sDone.%s Unplug and replug the adapter to apply, or rerun with %s--reload%s.\n' \
      "$BOLD" "$RST" "$BOLD" "$RST"
  else
    printf '%sDone.%s Now running with %s virtual display(s).\n' "$BOLD" "$RST" "$COUNT"
  fi
  printf 'To go back to the vendor default: %ssudo %s --reset%s\n' "$BOLD" "$0" "$RST"
fi
