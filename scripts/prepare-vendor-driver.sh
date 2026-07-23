#!/usr/bin/env bash
#
# prepare-vendor-driver.sh — make the official Silicon Motion installer succeed
#     on modern kernels (6.8+, tested on 6.17) by replacing the EVDI kernel
#     module it bundles (1.14.7, Nov 2024) with EVDI 1.15.0, which builds
#     against current kernels.
#
# Why this exists:
#   The vendor .run ships EVDI 1.14.7. On kernel 6.8+ its DKMS build fails with
#   "bad exit status: 2" / "Failed to install evdi ... to the kernel", so the
#   installer rolls itself back and /opt/siliconmotion is never created. The
#   repo's install.sh then has nothing to patch. Run this first: it swaps the
#   bundled evdi.tar.gz for a 1.15.0 one and leaves a ready-to-run vendor tree.
#
# Usage:
#   ./scripts/prepare-vendor-driver.sh --dir <extracted-vendor-dir>
#   ./scripts/prepare-vendor-driver.sh --run <SMIUSBDisplay-driver.x.y.z.run>
#     [--evdi-src <dir|tarball>]   use a local EVDI source (offline, no network)
#     [--evdi-tag <tag>]           git tag to clone from DisplayLink/evdi
#                                  (default: v1.15.0; needs network)
#     [--out <dir>]                where to write the patched copy
#     [--dry-run]                  print every action, change nothing
#     [--help]
#
# --dir  an already-extracted vendor folder (contains install.sh + evdi.tar.gz).
# --run  the vendor Makeself installer; extracted with --noexec (never run).
#
# This never runs the vendor installer and never touches the running system.
# It only produces a patched copy. Install it afterwards with, from that folder:
#     sudo ./install.sh
#
set -euo pipefail

EVDI_REPO="https://github.com/DisplayLink/evdi.git"
EVDI_TAG="v1.15.0"
SRC_RUN=""
SRC_DIR=""
EVDI_SRC=""
OUT_DIR=""
MODE="run"

if [ -t 1 ]; then BOLD=$'\e[1m'; GRN=$'\e[32m'; RED=$'\e[31m'; RST=$'\e[0m'; else BOLD=""; GRN=""; RED=""; RST=""; fi
say() { printf '%s==>%s %s\n' "$GRN" "$RST" "$1"; }
die() { printf '%serror:%s %s\n' "$RED" "$RST" "$1" >&2; exit 1; }
run() { if [ "$MODE" = "dry-run" ]; then printf '  [dry-run] %s\n' "$*"; else eval "$*"; fi; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)      SRC_DIR="${2:-}"; shift 2 ;;
    --run)      SRC_RUN="${2:-}"; shift 2 ;;
    --evdi-src) EVDI_SRC="${2:-}"; shift 2 ;;
    --evdi-tag) EVDI_TAG="${2:-}"; shift 2 ;;
    --out)      OUT_DIR="${2:-}"; shift 2 ;;
    --dry-run)  MODE="dry-run"; shift ;;
    -h|--help)  grep '^#' "$0" | grep -v '^#!' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
done

# ---- preflight -------------------------------------------------------------
for t in tar; do command -v "$t" >/dev/null 2>&1 || die "missing tool: $t"; done
[ -n "$SRC_DIR" ] || [ -n "$SRC_RUN" ] || die "give one of --dir <folder> or --run <installer.run> (see --help)."
[ -n "$SRC_DIR" ] && [ -n "$SRC_RUN" ] && die "use either --dir or --run, not both."

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# ---- 1. get the vendor tree (extracted, never executed) --------------------
VENDOR=""
if [ -n "$SRC_RUN" ]; then
  [ -f "$SRC_RUN" ] || die "vendor installer not found: $SRC_RUN"
  say "Extracting the vendor installer without running it (Makeself --noexec)"
  # Makeself self-extractors accept --noexec --keep --target to unpack only.
  run "bash '$SRC_RUN' --noexec --keep --target '$WORK/vendor' >/dev/null 2>&1 || sh '$SRC_RUN' --noexec --keep --target '$WORK/vendor' >/dev/null 2>&1"
  VENDOR="$WORK/vendor"
else
  [ -d "$SRC_DIR" ] || die "vendor folder not found: $SRC_DIR"
  VENDOR="$SRC_DIR"
fi
[ "$MODE" = "dry-run" ] || [ -f "$VENDOR/evdi.tar.gz" ] || die "no evdi.tar.gz in the vendor tree ($VENDOR) — is this the SMIUSBDisplay folder?"
[ "$MODE" = "dry-run" ] || [ -f "$VENDOR/install.sh" ] || die "no install.sh in the vendor tree ($VENDOR)."

# ---- 2. get the EVDI 1.15.0 source -----------------------------------------
EVDI_ROOT=""
resolve_evdi_root() { # find the dir holding module/dkms.conf under $1
  local base="$1" hit
  hit="$(find "$base" -type f -path '*/module/dkms.conf' 2>/dev/null | head -n1)"
  [ -n "$hit" ] && printf '%s\n' "$(dirname "$(dirname "$hit")")"
}
if [ -n "$EVDI_SRC" ]; then
  if [ -d "$EVDI_SRC" ]; then
    say "Using local EVDI source tree: $EVDI_SRC"
    EVDI_ROOT="$(resolve_evdi_root "$EVDI_SRC")"
  elif [ -f "$EVDI_SRC" ]; then
    say "Extracting local EVDI source tarball: $EVDI_SRC"
    run "mkdir -p '$WORK/evdi' && tar xf '$EVDI_SRC' -C '$WORK/evdi'"
    EVDI_ROOT="$(resolve_evdi_root "$WORK/evdi")"
  else
    die "EVDI source not found: $EVDI_SRC"
  fi
else
  command -v git >/dev/null 2>&1 || die "git needed to fetch EVDI $EVDI_TAG (or pass --evdi-src a local copy)."
  say "Cloning EVDI $EVDI_TAG from $EVDI_REPO"
  run "git clone --depth 1 --branch '$EVDI_TAG' '$EVDI_REPO' '$WORK/evdi' >/dev/null 2>&1"
  EVDI_ROOT="$(resolve_evdi_root "$WORK/evdi")"
fi
if [ "$MODE" != "dry-run" ]; then
  [ -n "$EVDI_ROOT" ] && [ -d "$EVDI_ROOT/module" ] && [ -d "$EVDI_ROOT/library" ] \
    || die "could not locate the EVDI source root (needs module/ and library/)."
  NEW_VER="$(awk -F= '/PACKAGE_VERSION/{print $2}' "$EVDI_ROOT/module/dkms.conf" | tr -d ' ')"
  say "EVDI source version: ${NEW_VER:-unknown}"
fi

# ---- 3. report the old bundled version -------------------------------------
if [ "$MODE" != "dry-run" ]; then
  OLD_VER="$(tar xzf "$VENDOR/evdi.tar.gz" -O ./module/dkms.conf 2>/dev/null | awk -F= '/PACKAGE_VERSION/{print $2}' | tr -d ' ' || true)"
  say "Vendor bundles EVDI ${OLD_VER:-?} — replacing it with ${NEW_VER:-?}"
fi

# ---- 4. produce the patched copy -------------------------------------------
if [ -z "$OUT_DIR" ]; then
  OUT_DIR="$(cd "$(dirname "$VENDOR")" && pwd)/$(basename "$VENDOR")-patched-evdi${NEW_VER:-1.15.0}"
fi
say "Writing patched copy to: $OUT_DIR"
run "rm -rf '$OUT_DIR' && cp -a '$VENDOR' '$OUT_DIR'"
run "cp -a '$OUT_DIR/evdi.tar.gz' '$OUT_DIR/evdi.tar.gz.orig'"
say "Repacking evdi.tar.gz from EVDI ${NEW_VER:-1.15.0}"
run "tar czf '$OUT_DIR/evdi.tar.gz' -C '${EVDI_ROOT:-<evdi-src>}' ."

# ---- 5. verify -------------------------------------------------------------
if [ "$MODE" != "dry-run" ]; then
  GOT="$(tar xzf "$OUT_DIR/evdi.tar.gz" -O ./module/dkms.conf 2>/dev/null | awk -F= '/PACKAGE_VERSION/{print $2}' | tr -d ' ')"
  [ "$GOT" = "$NEW_VER" ] || die "verification failed: repacked evdi.tar.gz reports '$GOT', expected '$NEW_VER'."
  printf '\n%sReady.%s The vendor driver in\n  %s\n now bundles EVDI %s and will build on kernel 6.8+.\n' \
    "$BOLD" "$RST" "$OUT_DIR" "$NEW_VER"
  printf 'Install it next (needs your password):\n  %scd "%s" && sudo ./install.sh%s\n' "$BOLD" "$OUT_DIR" "$RST"
  printf 'Then apply the desktop fixes from this repo:\n  %ssudo ./install.sh%s   (this repo, from its own folder)\n' "$BOLD" "$RST"
else
  printf '\n%sDry run complete. No changes were made.%s\n' "$BOLD" "$RST"
fi
