#!/usr/bin/env bash
# Uninstall atelier from this Mac. Asks before doing anything destructive.
#
# What it removes:
#   1. The atelier OrbStack VM (and any other VMs whose name starts with
#      the same prefix — opt out by editing DEVBOX_PREFIX).
#   2. The ~/.config/environment.d/host-proxy.conf passthrough file
#      inside each VM (best-effort).
#   3. With --all: OrbStack itself (/Applications/OrbStack.app and ~/Library/...).
#   4. With --all: the bin/devbox symlink in /usr/local/bin if you created one.
#
# What it does NOT remove:
#   - Any files on the host outside the ones OrbStack itself owns. Your
#     projects in ~/Code/crack stay put — the host filesystem was never
#     modified.
set -euo pipefail

VM_NAME="${DEVBOX_VM:-atelier}"
# Extra VMs sharing this prefix get cleaned up too. Defaults to the VM name so
# the common case (just "atelier") works; set DEVBOX_PREFIX to widen the sweep.
DEVBOX_PREFIX="${DEVBOX_PREFIX:-$VM_NAME}"
DO_ALL=0
[[ "${1:-}" == "--all" ]] && DO_ALL=1

log()  { printf '\033[1;34m[uninstall]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[uninstall]\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[uninstall]\033[0m %s\n' "$*"; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  log "not on macOS; nothing to do."
  exit 0
fi

command -v orbctl >/dev/null 2>&1 || {
  log "orbctl not on PATH; OrbStack is not installed. nothing to remove."
  if [[ $DO_ALL -eq 0 ]]; then exit 0; fi
}

if command -v orbctl >/dev/null 2>&1; then
  log "VMs that match prefix '$DEVBOX_PREFIX':"
  orbctl list 2>/dev/null | awk -v p="$DEVBOX_PREFIX" 'NR>0 && $1 ~ "^"p {print "  - "$0}' || true

  warn "this will DELETE the VM '$VM_NAME' (and any other '$DEVBOX_PREFIX*' VMs)"
  read -rp "type 'yes' to continue: " confirm
  [[ "$confirm" == "yes" ]] || { log "aborted."; exit 0; }

  # Best-effort: remove passthrough file before deletion
  if orbctl list 2>/dev/null | awk '{print $1}' | grep -qx "$VM_NAME"; then
    orbctl run -m "$VM_NAME" bash -c 'rm -f ~/.config/environment.d/host-proxy.conf' 2>/dev/null || true
    log "deleting VM $VM_NAME"
    orbctl delete "$VM_NAME" --force 2>/dev/null || true
  fi

  # Also wipe any other dev-* VMs (for users who created more)
  for v in $(orbctl list 2>/dev/null | awk -v p="$DEVBOX_PREFIX" '$1 ~ "^"p {print $1}'); do
    [[ "$v" == "$VM_NAME" ]] && continue
    log "deleting extra VM $v"
    orbctl delete "$v" --force 2>/dev/null || true
  done
  ok "VMs removed"
fi

if [[ $DO_ALL -eq 1 ]]; then
  warn "removing OrbStack itself"
  if [[ -d /Applications/OrbStack.app ]]; then
    if sudo rm -rf /Applications/OrbStack.app; then ok "OrbStack.app removed"; else warn "could not remove /Applications/OrbStack.app"; fi
  fi
  if [[ -d "$HOME/.orbstack" ]]; then
    if rm -rf "$HOME/.orbstack"; then ok "$HOME/.orbstack removed"; else warn "could not remove $HOME/.orbstack"; fi
  fi
  if [[ -d "$HOME/Library/Application Support/OrbStack" ]]; then
    if rm -rf "$HOME/Library/Application Support/OrbStack"; then ok "OrbStack support dir removed"; else warn "could not remove OrbStack support dir"; fi
  fi
  # Optional: remove a devbox symlink the user may have placed in /usr/local/bin
  if [[ -L /usr/local/bin/devbox ]]; then
    if sudo rm -f /usr/local/bin/devbox; then ok "/usr/local/bin/devbox symlink removed"; fi
  fi
  if command -v brew >/dev/null 2>&1 && brew list --cask 2>/dev/null | grep -q orbstack; then
    if brew uninstall --cask orbstack; then ok "brew cask removed"; else warn "brew uninstall failed (run manually)"; fi
  fi
fi

ok "done."
