#!/usr/bin/env bash
# Install OrbStack on macOS. Prefers Homebrew Cask; falls back to a direct
# download from orbstack.dev if brew is missing.
#
# Idempotent: a no-op if OrbStack is already installed at /Applications.
set -euo pipefail

log()  { printf '\033[1;34m[install-orbstack]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[install-orbstack]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[install-orbstack]\033[0m %s\n' "$*" >&2; exit 1; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  die "OrbStack is macOS-only. abort."
fi

if [[ -d /Applications/OrbStack.app ]] && command -v orbctl >/dev/null 2>&1; then
  ok "OrbStack already installed: $(defaults read /Applications/OrbStack.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo 'unknown version')"
  exit 0
fi

# Prefer Homebrew Cask — it's the cleanest path on Apple Silicon and Intel.
if command -v brew >/dev/null 2>&1; then
  log "installing via Homebrew Cask"
  brew install --cask orbstack
  ok "OrbStack installed"
  log "open /Applications/OrbStack.app to finish first-run setup (one-time)"
  exit 0
fi

# Fallback: download the latest .dmg straight from orbstack.dev. The site
# detects the host arch and serves the right build.
log "Homebrew not found; downloading OrbStack.dmg from orbstack.dev"
arch="$(uname -m)"
case "$arch" in
  arm64) asset="OrbStack_2.2.1_arm64.dmg" ;;
  x86_64) asset="OrbStack_2.2.1_x64.dmg" ;;
  *) die "unsupported arch: $arch" ;;
esac
url="https://orbstack.dev/download/${asset}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

log "fetching $url"
curl -fL --retry 3 -o "$tmp/$asset" "$url" || die "download failed — open https://orbstack.dev/download in a browser and install manually"

log "mounting dmg"
hdiutil attach -nobrowse -quiet "$tmp/$asset" || die "failed to mount $asset"

# The .dmg exposes OrbStack.app; copy it to /Applications.
mount_point="$(/usr/bin/env | grep -E '^TMPDIR|^HOME' | head -1 >/dev/null; find /Volumes -maxdepth 1 -name 'OrbStack*' -type d 2>/dev/null | head -1)"
[[ -d "$mount_point/OrbStack.app" ]] || die "could not find OrbStack.app inside the dmg"

log "copying OrbStack.app to /Applications (may prompt for admin password)"
sudo /bin/cp -R "$mount_point/OrbStack.app" /Applications/ || die "copy failed"
sudo /usr/bin/xattr -dr com.apple.quarantine /Applications/OrbStack.app 2>/dev/null || true
hdiutil detach -quiet "$mount_point" || true

ok "OrbStack installed at /Applications/OrbStack.app"
log "open /Applications/OrbStack.app to finish first-run setup (one-time)"
