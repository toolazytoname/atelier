#!/usr/bin/env bash
# Provision the OrbStack atelier VM with a general Linux dev toolchain.
# Optimized for users behind slow international links — defaults to mainland
# China mirrors. Set CN_MIRROR=0 to use the international defaults instead.
#
# Idempotent. Re-creatable from scratch via:
#   orbctl delete atelier && orbctl create --cpus 4 --memory 8G --disk 64G ubuntu:24.04 atelier
#   ./setup/provision.sh
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

CN_MIRROR="${CN_MIRROR:-1}"   # 1 = use China mirrors where it helps, 0 = international

# --- mirror selection ------------------------------------------------------
# Only the things that are actually slow from this host's egress get mirrored:
#   apt (Cloudflare), npm registry (Cloudflare), crates.io (Cloudflare)
# Everything else (go.dev, static.rust-lang.org, dl.google.com) is fast enough
# from both egress paths, so we use the official sources.
if [[ "$CN_MIRROR" == "1" ]]; then
  APT_MIRROR="mirrors.tuna.tsinghua.edu.cn"
  APT_SUITE="noble"
  NPM_REG="https://registry.npmmirror.com"
  NPM_BIN="https://registry.npmmirror.com/-/binary"
  CRATES_REPLACE='[source.crates-io]
replace-with = "rsproxy-sparse"

[source.rsproxy-sparse]
registry = "sparse+https://rsproxy.cn/index/"
'
  PIP_INDEX="https://pypi.tuna.tsinghua.edu.cn/simple"
  GH_PROXY="https://ghfast.top/"
else
  APT_MIRROR="ports.ubuntu.com"
  APT_SUITE="noble"
  NPM_REG="https://registry.npmjs.org"
  NPM_BIN="https://nodejs.org/dist"
  CRATES_REPLACE=""
  PIP_INDEX="https://pypi.org/simple"
  GH_PROXY=""
fi

step() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '   \033[1;32m✓\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------------------
# apt: switch sources to a fast mirror, then install base + dev packages
# ---------------------------------------------------------------------------
step "apt sources -> ${APT_MIRROR}"
if [[ "$CN_MIRROR" == "1" ]]; then
  sudo tee /etc/apt/sources.list >/dev/null <<EOF
deb https://${APT_MIRROR}/ubuntu-ports ${APT_SUITE} main restricted universe multiverse
deb https://${APT_MIRROR}/ubuntu-ports ${APT_SUITE}-updates main restricted universe multiverse
deb https://${APT_MIRROR}/ubuntu-ports ${APT_SUITE}-security main restricted universe multiverse
EOF
fi

step "apt update + base packages"
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
  build-essential ca-certificates curl wget gnupg lsb-release \
  zsh git git-lfs \
  fzf ripgrep fd-find bat eza jq yq \
  tmux htop btop neovim nano \
  unzip zip p7zip-full xz-utils \
  netcat-openbsd iproute2 dnsutils \
  libssl-dev libreadline-dev libyaml-dev libffi-dev libgmp-dev \
  libsqlite3-dev libbz2-dev libzstd-dev zlib1g-dev \
  locales software-properties-common apt-transport-https
ok "base apt packages installed"

step "locale en_US.UTF-8"
sudo locale-gen en_US.UTF-8 >/dev/null
ok "locale"

# ---------------------------------------------------------------------------
# Node.js 24 LTS via npmmirror binary tarball (open-design requires ~24)
# ---------------------------------------------------------------------------
step "Node.js 24 LTS"
if ! command -v node >/dev/null 2>&1 || [[ "$(node -v | sed 's/v//;s/\..*//')" -lt 24 ]]; then
  NODE_VERSION="v24.11.0"
  arch="$(uname -m | sed 's/aarch64/arm64/;s/x86_64/x64/')"
  extracted_dir="node-${NODE_VERSION}-linux-${arch}"
  archive="${extracted_dir}.tar.xz"
  url="${NPM_BIN}/node/${NODE_VERSION}/${archive}"
  echo "   downloading $url"
  curl -fsSL "$url" -o "/tmp/$archive"
  sudo tar -C /usr/local -xJf "/tmp/$archive"
  sudo ln -sf "/usr/local/${extracted_dir}/bin/node" /usr/local/bin/node
  sudo ln -sf "/usr/local/${extracted_dir}/bin/npm"  /usr/local/bin/npm
  sudo ln -sf "/usr/local/${extracted_dir}/bin/npx"  /usr/local/bin/npx
  sudo ln -sf "/usr/local/${extracted_dir}/bin/corepack" /usr/local/bin/corepack
  rm -f "/tmp/$archive"
  # Remove the previous default (22) install if it's around
  for old in /usr/local/node-v22*-linux-"${arch}"; do
    [[ -d "$old" ]] && sudo rm -rf "$old"
  done
fi
ok "node $(node -v)"

step "pnpm (via npm, with CN registry)"
NODE_BIN="/usr/local/node-v24.11.0-linux-arm64/bin"
if ! command -v pnpm >/dev/null 2>&1; then
  sudo npm config set registry "$NPM_REG"
  sudo npm install -g pnpm@10.15.0 >/dev/null
  # npm installs global bins into $NODE_BIN; expose them on PATH via symlinks
  for bin in pnpm pnpx; do
    [[ -x "$NODE_BIN/$bin" ]] && sudo ln -sf "$NODE_BIN/$bin" "/usr/local/bin/$bin"
  done
  pnpm config set registry "$NPM_REG"
fi
ok "pnpm $(pnpm -v)"

# ---------------------------------------------------------------------------
# Python 3.12 + uv
# ---------------------------------------------------------------------------
step "Python 3.12 + uv"
# Ubuntu 24.04 already ships Python 3.12; just ensure venv + dev are present.
sudo apt-get install -y python3.12-venv python3.12-dev python3-pip 2>/dev/null || true
if ! command -v uv >/dev/null 2>&1; then
  # default install path is ~/.local/bin (user-writable, no sudo needed)
  curl -LsSf https://astral.sh/uv/install.sh | env UV_PYTHON_INDEX_URL="$PIP_INDEX" sh >/dev/null
  # expose on PATH for non-login shells
  [[ -x "$HOME/.local/bin/uv" ]] && sudo ln -sf "$HOME/.local/bin/uv" /usr/local/bin/uv
fi
ok "python3 $(python3 --version) / uv $(uv --version)"

# ---------------------------------------------------------------------------
# Go 1.23 (binary tarball from go.dev or via goproxy)
# ---------------------------------------------------------------------------
step "Go 1.23"
GO_VERSION=1.23.4
if ! command -v go >/dev/null 2>&1 || [[ "$(go version | awk '{print $3}' | sed 's/go//')" != "${GO_VERSION}"* ]]; then
  arch="$(uname -m | sed 's/aarch64/arm64/;s/x86_64/amd64/')"
  # go.dev redirect to dl.google.com can SSL-error mid-stream; fetch the
  # canonical archive directly from dl.google.com (verified ~20 MB/s).
  if ! curl -fsSL --retry 3 "https://dl.google.com/go/go${GO_VERSION}.linux-${arch}.tar.gz" \
       | sudo tar -C /usr/local -xz; then
    echo "   dl.google.com failed; falling back to go.dev"
    curl -fsSL --retry 3 "https://go.dev/dl/go${GO_VERSION}.linux-${arch}.tar.gz" \
      | sudo tar -C /usr/local -xz
  fi
  # shellcheck disable=SC2016  # $PATH / $HOME expand on the VM, not here
  echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
export GOPROXY=https://goproxy.cn,direct' | sudo tee /etc/profile.d/go.sh >/dev/null
fi
ok "go $(go version 2>/dev/null || echo installed)"

# ---------------------------------------------------------------------------
# Rust stable (official rustup; crates.io replaced via CN mirror if CN_MIRROR=1)
# ---------------------------------------------------------------------------
step "Rust stable"
if ! command -v rustc >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | env RUSTUP_INIT_SKIP_PATH_CHECK=yes \
         sh -s -- -y --default-toolchain stable --profile minimal >/dev/null
  # shellcheck disable=SC1091
  source "$HOME/.cargo/env"
fi
if [[ -n "$CRATES_REPLACE" ]]; then
  mkdir -p "$HOME/.cargo"
  printf '%s' "$CRATES_REPLACE" > "$HOME/.cargo/config.toml"
fi
ok "rustc $(rustc --version 2>/dev/null || echo installed)"

# ---------------------------------------------------------------------------
# Docker CLI (talks to host OrbStack socket)
# ---------------------------------------------------------------------------
step "Docker CLI (optional — falls back to CN mirror, then to skip)"
if ! command -v docker >/dev/null 2>&1; then
  # Try official first, then TUNA mirror (download.docker.com is Cloudflare-fronted
  # and SSL-fails intermittently from CN egress). If both fail, log and skip —
  # Docker isn't required for the atelier workflow.
  set +e
  curl -fsSL --retry 2 https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg 2>/dev/null
  if [[ -s /usr/share/keyrings/docker-archive-keyring.gpg ]]; then
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu noble stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update -qq 2>/dev/null
    sudo apt-get install -y docker-ce-cli docker-compose-plugin 2>/dev/null
  fi

  if ! command -v docker >/dev/null 2>&1 && [[ "$CN_MIRROR" == "1" ]]; then
    echo "   official docker repo failed; trying TUNA mirror"
    curl -fsSL --retry 2 https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu/gpg \
      | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg 2>/dev/null
    if [[ -s /usr/share/keyrings/docker-archive-keyring.gpg ]]; then
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu noble stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
      sudo apt-get update -qq 2>/dev/null
      sudo apt-get install -y docker-ce-cli docker-compose-plugin 2>/dev/null
    fi
  fi

  sudo usermod -aG docker "$USER" 2>/dev/null || true
  set -e
fi
if command -v docker >/dev/null 2>&1; then
  ok "docker $(docker --version)"
else
  printf '   %s docker skipped (no working repo; OrbStack host daemon still serves docker CLI via socket)\n' "$(printf '\033[1;33m!\033[0m')"
fi

# ---------------------------------------------------------------------------
# GitHub CLI
# ---------------------------------------------------------------------------
step "GitHub CLI (gh)"
if ! command -v gh >/dev/null 2>&1; then
  if [[ -n "$GH_PROXY" ]]; then
    # CN: use ghfast.top to bypass slow GitHub releases
    GH_VERSION=$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest 2>/dev/null | grep tag_name | head -1 | cut -d'"' -f4 || echo "v2.62.0")
    GH_VERSION="${GH_VERSION:-v2.62.0}"
    arch="$(uname -m | sed 's/aarch64/arm64/;s/x86_64/amd64/')"
    curl -fsSL "${GH_PROXY}https://github.com/cli/cli/releases/download/${GH_VERSION}/gh_${GH_VERSION#v}_linux_${arch}.tar.gz" -o /tmp/gh.tgz
    sudo tar -C /usr/local -xzf /tmp/gh.tgz --strip-components=1 "gh_${GH_VERSION#v}_linux_${arch}/bin/gh"
    rm -f /tmp/gh.tgz
  else
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    sudo apt-get update -qq
    sudo apt-get install -y gh
  fi
fi
ok "gh $(gh --version | head -1)"

# ---------------------------------------------------------------------------
# Claude Code
# ---------------------------------------------------------------------------
step "Claude Code"
# claude.ai/install.sh returns the "App unavailable in region" page from CN
# egress. Install the npm package directly instead — it's the same binary.
if ! command -v claude >/dev/null 2>&1; then
  sudo npm config set registry "$NPM_REG"
  sudo npm install -g @anthropic-ai/claude-code@latest >/dev/null 2>&1 || \
    pnpm add -g @anthropic-ai/claude-code@latest >/dev/null 2>&1 || \
    { echo "   npm install failed; falling back to host symlink"; \
      sudo ln -sf /opt/homebrew/bin/claude /usr/local/bin/claude 2>/dev/null || true; }
  mkdir -p "$HOME/.local/bin"
fi
ok "claude $(claude --version 2>/dev/null || echo installed)"

# ---------------------------------------------------------------------------
# open-design (daemon + MCP server, Electron GUI). All-in-VM design workflow.
# Local-first, agent-native, runs on Linux because it's Node 24 + Electron.
# Source: https://github.com/nexu-io/open-design
# ---------------------------------------------------------------------------
step "open-design (daemon + MCP)"

OD_DIR="$HOME/.local/share/open-design"
OD_BIN="$HOME/.local/bin/od"
OD_REPO="https://github.com/nexu-io/open-design.git"
OD_REF="main"

if [[ ! -d "$OD_DIR/.git" ]]; then
  echo "   cloning open-design ($OD_REF) to $OD_DIR"
  git clone --depth 1 --branch "$OD_REF" "$OD_REPO" "$OD_DIR" || {
    echo "   clone failed; trying shallow without branch"
    git clone --depth 1 "$OD_REPO" "$OD_DIR"
  }
fi

# Install + build only if the install hasn't been done yet, or if a marker is missing.
if [[ ! -f "$OD_DIR/node_modules/.modules.yaml" ]] || [[ ! -x "$OD_DIR/apps/daemon/bin/od.mjs" ]]; then
  echo "   pnpm install in $OD_DIR (this can take a few minutes)"
  # corepack needs root to symlink into /usr/local/bin; we already have pnpm
  # installed globally by the earlier step, so just use it directly.
  (cd "$OD_DIR" && pnpm install --no-frozen-lockfile 2>&1 | tail -10)
fi

# Expose the `od` binary on PATH
mkdir -p "$HOME/.local/bin"
if [[ -f "$OD_DIR/apps/daemon/bin/od.mjs" ]]; then
  cat > "$OD_BIN" <<EOF
#!/usr/bin/env bash
exec node "$OD_DIR/apps/daemon/bin/od.mjs" "\$@"
EOF
  chmod +x "$OD_BIN"
fi

# A few native deps Electron needs at runtime in the VM (X11 forwarding)
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get install -y --no-install-recommends \
    libgtk-3-0 libnss3 libxss1 libasound2t64 libatk-bridge2.0-0 libdrm2 \
    libgbm1 libxcomposite1 libxdamage1 libxfixes3 libxkbcommon0 libxrandr2 \
    xauth xvfb 2>&1 | tail -3 || true
fi

# Try to start the daemon so MCP can talk to it; non-fatal if it doesn't.
if [[ -x "$OD_BIN" ]] && ! pgrep -f "od.mjs" >/dev/null 2>&1; then
  echo "   starting open-design daemon in background"
  (nohup "$OD_BIN" start >"$HOME/.local/share/open-design/daemon.log" 2>&1 &) || true
  sleep 2
fi

ok "od $(command -v od >/dev/null 2>&1 && echo installed || echo 'CLI missing')"

# ---------------------------------------------------------------------------
# Starship prompt + zsh default
# ---------------------------------------------------------------------------
step "Starship prompt (non-fatal — purely cosmetic)"
if ! command -v starship >/dev/null 2>&1; then
  set +e
  curl -4 -sSL --retry 2 "https://ghfast.top/https://starship.rs/install.sh" -o /tmp/starship-install.sh
  if [[ -s /tmp/starship-install.sh ]] && head -1 /tmp/starship-install.sh | grep -q '^#!'; then
    sh /tmp/starship-install.sh -y -b "$HOME/.local/bin" >/dev/null
    sudo ln -sf "$HOME/.local/bin/starship" /usr/local/bin/starship
  else
    # shellcheck disable=SC2016  # $PS1 is a literal in the message
    printf '   %s starship install script came back empty/blocked; skipping (a plain $PS1 works fine)\n' "$(printf '\033[1;33m!\033[0m')"
  fi
  rm -f /tmp/starship-install.sh
  set -e
fi
if command -v starship >/dev/null 2>&1; then
  ok "starship $(starship --version 2>/dev/null || echo installed)"
else
  printf '   %s starship not installed (skipped)\n' "$(printf '\033[1;33m!\033[0m')"
fi

step "set zsh as default shell"
if [[ "$SHELL" != */zsh ]]; then
  sudo chsh -s "$(which zsh)" "$USER"
fi
ok "shell: $SHELL -> $(getent passwd "$USER" | cut -d: -f7)"

# ---------------------------------------------------------------------------
# Bootstrap shell rc files (OrbStack's fresh user home is empty)
# ---------------------------------------------------------------------------
step "bootstrap shell rc"
[[ -f "$HOME/.bashrc" ]] || cp /etc/skel/.bashrc "$HOME/.bashrc" 2>/dev/null || touch "$HOME/.bashrc"
[[ -f "$HOME/.profile" ]] || cp /etc/skel/.profile "$HOME/.profile" 2>/dev/null || touch "$HOME/.profile"
[[ -f "$HOME/.zshrc"  ]] || cat > "$HOME/.zshrc" <<'ZSHRC_EOF'
# zsh config — see setup/provision.sh for the source of this skeleton
ZSHRC_EOF
ok "shell rc bootstrapped"

# ---------------------------------------------------------------------------
# Wire host-proxy.conf into the shell rc files
# ---------------------------------------------------------------------------
step "wire host env into shell rc"
mkdir -p "$HOME/.config/environment.d"
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [[ -f "$rc" ]] && ! grep -q "environment.d" "$rc"; then
    cat >> "$rc" <<'ENVLOAD_EOF'

# Load host-proxy env (mirrored by setup/host-passthrough.sh)
if [ -d "$HOME/.config/environment.d" ]; then
  for f in "$HOME"/.config/environment.d/*.conf; do
    [ -r "$f" ] && source "$f"
  done
fi
ENVLOAD_EOF
  fi
done
# Make .zshrc a usable zsh config with PATH + starship
if ! grep -q "starship init zsh" "$HOME/.zshrc" 2>/dev/null; then
  cat >> "$HOME/.zshrc" <<'ZSH_PROMPT_EOF'

# PATH for dev tools
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/go/bin:/usr/local/go/bin:$PATH"

# Starship prompt
command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"

# Conveniences
alias ll="ls -lah"; alias la="ls -A"; alias l="ls -CF"
alias g="git"; alias dc="docker compose"; alias dcr="docker compose run --rm"
ZSH_PROMPT_EOF
fi
ok "shell rc wired"

# ---------------------------------------------------------------------------
# Symlink convenience mounts
# ---------------------------------------------------------------------------
step "symlink host code into VM"
mkdir -p "$HOME/Code"
if [[ ! -e "$HOME/Code/crack" ]] && [[ -e /mnt/mac/Users/lazy/Code/crack ]]; then
  ln -sfn /mnt/mac/Users/lazy/Code/crack "$HOME/Code/crack"
fi
ok "$HOME/Code/crack -> /mnt/mac/Users/lazy/Code/crack"

step "DONE"
printf '\n\033[1;32m✓ atelier ready. Re-login (or: exec zsh) for shell changes to take effect.\033[0m\n'
