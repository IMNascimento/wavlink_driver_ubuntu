#!/usr/bin/env bash
#
# diagnose.sh — read-only health check for the SM768 USB display driver.
#
# Changes nothing on your system. Run it first, before install.sh, to see
# whether your machine matches the scenario this fix targets and whether the
# fix is already applied.
#
# Usage: ./scripts/diagnose.sh
#
set -uo pipefail

USB_ID="090c:0768"
SMI_DIR="/opt/siliconmotion"

# ---- pretty output ---------------------------------------------------------
if [ -t 1 ]; then
  BOLD=$'\e[1m'; DIM=$'\e[2m'; RED=$'\e[31m'; GRN=$'\e[32m'; YLW=$'\e[33m'; RST=$'\e[0m'
else
  BOLD=""; DIM=""; RED=""; GRN=""; YLW=""; RST=""
fi
ok()   { printf '  %s[ ok ]%s %s\n'   "$GRN" "$RST" "$1"; }
warn() { printf '  %s[warn]%s %s\n'   "$YLW" "$RST" "$1"; }
bad()  { printf '  %s[fail]%s %s\n'   "$RED" "$RST" "$1"; }
info() { printf '  %s[info]%s %s\n'   "$DIM" "$RST" "$1"; }
head() { printf '\n%s%s%s\n' "$BOLD" "$1" "$RST"; }

head "System"
if command -v lsb_release >/dev/null 2>&1; then
  info "$(lsb_release -ds 2>/dev/null)"
elif [ -r /etc/os-release ]; then
  info "$(. /etc/os-release; echo "$PRETTY_NAME")"
fi
info "Kernel: $(uname -r)"
info "Session: ${XDG_SESSION_TYPE:-unknown} (${XDG_CURRENT_DESKTOP:-?})"
if command -v lspci >/dev/null 2>&1; then
  while IFS= read -r line; do info "GPU: $line"; done < <(lspci 2>/dev/null | grep -Ei 'vga|3d|display')
fi

head "USB display adapter"
if command -v lsusb >/dev/null 2>&1 && lsusb 2>/dev/null | grep -qi "090c:"; then
  ok "Silicon Motion adapter detected: $(lsusb | grep -i '090c:' | head -n1 | sed 's/^/    /')"
else
  warn "No 090c: adapter on the bus right now (that's fine if it's unplugged)."
fi

head "Vendor driver"
if [ -d "$SMI_DIR" ]; then
  ok "Vendor driver present at $SMI_DIR"
  [ -x "$SMI_DIR/SMIUSBDisplayManager" ] && ok "Daemon binary found." \
    || bad "Daemon binary missing — reinstall the official Silicon Motion driver first."
  [ -f "$SMI_DIR/evdi.tar.gz" ] && ok "EVDI source archive present (needed to build the fix)." \
    || warn "No evdi.tar.gz in $SMI_DIR — install.sh will look for a local copy instead."
else
  bad "$SMI_DIR not found. Install the official Silicon Motion driver before this fix."
fi

head "Fix status"
if [ -f "$SMI_DIR/libevdi.so.orig" ]; then
  ok "Backup libevdi.so.orig exists — the fix appears to be installed."
else
  info "No libevdi.so.orig backup — the fix has not been applied yet."
fi
if [ -f /etc/modules-load.d/evdi.conf ]; then
  bad "/etc/modules-load.d/evdi.conf exists — evdi is force-loaded at boot (gray-screen risk)."
else
  ok "evdi is not force-loaded at boot."
fi
if systemctl is-enabled smiusbdisplay.service >/dev/null 2>&1; then
  state="$(systemctl is-enabled smiusbdisplay.service 2>/dev/null)"
  if [ "$state" = "masked" ]; then
    warn "smiusbdisplay.service is masked — it will NOT start on plug until unmasked."
  else
    ok "smiusbdisplay.service is $state (starts on plug via udev)."
  fi
else
  info "smiusbdisplay.service not registered yet."
fi

head "Crash signature in logs"
if journalctl -b -t SMIUSBDisplayManager 2>/dev/null | grep -qiE 'segfault|signal 11|SIGSEGV'; then
  bad "Found a daemon segfault this boot — this is exactly what the fix resolves."
elif journalctl -k -b 2>/dev/null | grep -qi 'SMIUSBDisplayManager.*segfault'; then
  bad "Kernel logged a SMIUSBDisplayManager segfault — the fix resolves it."
else
  info "No daemon segfault found in this boot's logs (run with sudo for full journal access)."
fi

head "Build dependencies (for building the patched libevdi)"
for tool in gcc make pkg-config patch tar; do
  if command -v "$tool" >/dev/null 2>&1; then ok "$tool"; else bad "$tool missing — apt install build-essential pkg-config patch"; fi
done
if pkg-config --exists libdrm 2>/dev/null; then
  ok "libdrm ($(pkg-config --modversion libdrm))"
else
  bad "libdrm dev headers missing — apt install libdrm-dev"
fi

printf '\n%sDiagnosis complete. Nothing was changed.%s\n' "$BOLD" "$RST"
