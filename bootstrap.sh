#!/usr/bin/env bash
#
# bootstrap.sh — idempotent machine bootstrap
#
# Safe to re-run: every step checks current state before acting.
#
# Steps:
#   0. Install Xcode Command Line Tools (macOS only, if missing)
#   1. Install Homebrew (macOS only, if missing)
#   2. Install Claude Code (if missing)
#   3. Install uv, gh — brew on macOS, pacman on Arch (if missing)
#   4. gh auth login (if not already authenticated)
#   5. Install ansible via uv tool, plus kewlfft.aur collection (Arch only)
#   6. [commented out] gh clone repos to ~/repos
#   7. [commented out] run ansible playbook
#
set -euo pipefail

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }

OS="$(uname -s)"

# ---------------------------------------------------------------------------
# ~/.local/bin on PATH — uv tool installs (step 5) and Claude Code's
# native installer (step 2) both land executables here. Only added if
# missing, and only for this script's own session.
# ---------------------------------------------------------------------------
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  export PATH="$HOME/.local/bin:$PATH"
  log "Added ~/.local/bin to PATH for this session."
  log "Add it permanently via your chezmoi-managed shell rc so future shells pick it up too."
else
  log "~/.local/bin already on PATH — skipping"
fi

# ---------------------------------------------------------------------------
# 0. Xcode Command Line Tools (macOS only)
#
# git, Homebrew, and most compiled brew formulae need these. On a fresh
# Mac they aren't present, so the first thing that needs them (e.g. `git
# init`) pops a GUI installer dialog instead of just working. Trigger it
# explicitly up front and block until it's actually done, rather than
# letting some later step surprise you with a dialog mid-run.
# ---------------------------------------------------------------------------
if [[ "$OS" == "Darwin" ]]; then
  if ! xcode-select -p >/dev/null 2>&1; then
    log "Xcode Command Line Tools not found — triggering install"
    xcode-select --install >/dev/null 2>&1 || true

    log "Waiting for install to complete — approve the GUI dialog that just opened"
    until xcode-select -p >/dev/null 2>&1; do
      sleep 5
    done
    log "Xcode Command Line Tools installed"
  else
    log "Xcode Command Line Tools already installed — skipping"
  fi
fi

# ---------------------------------------------------------------------------
# 1. Homebrew (macOS only — Arch uses pacman, see step 3)
# ---------------------------------------------------------------------------
if [[ "$OS" == "Darwin" ]]; then
  if ! command -v brew >/dev/null 2>&1; then
    log "Homebrew not found — installing from https://brew.sh"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Put brew on PATH for the rest of this script's execution.
    # (Location differs: Apple Silicon vs Intel Mac.)
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi

    log "Homebrew installed. Add the shellenv line above to your shell rc"
    log "(chezmoi-managed .zshrc) so future shells pick it up automatically."
  else
    log "Homebrew already installed — skipping"
  fi
else
  log "Not macOS — skipping Homebrew (using pacman instead, see next step)"
fi

# ---------------------------------------------------------------------------
# 2. Claude Code
# ---------------------------------------------------------------------------
if ! command -v claude >/dev/null 2>&1; then
  log "Claude Code not found — installing from https://code.claude.com/docs/en/quickstart"
  curl -fsSL https://claude.ai/install.sh | bash
else
  log "Claude Code already installed ($(claude --version 2>/dev/null || echo 'version unknown')) — skipping"
fi

# ---------------------------------------------------------------------------
# 3. uv and gh — brew on macOS, pacman on Arch
# ---------------------------------------------------------------------------
log "Ensuring uv and gh are installed"
if [[ "$OS" == "Darwin" ]]; then
  brew install uv gh
elif [[ "$OS" == "Linux" ]] && command -v pacman >/dev/null 2>&1; then
  sudo pacman -S --needed --noconfirm uv github-cli
else
  echo "Unsupported OS/package manager — install uv and gh manually, then re-run." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 4. gh auth login
# ---------------------------------------------------------------------------
if ! gh auth status >/dev/null 2>&1; then
  log "gh not authenticated — starting login flow"
  gh auth login
else
  log "gh already authenticated — skipping"
fi

# ---------------------------------------------------------------------------
# 5. ansible via uv tool, plus the kewlfft.aur collection (Arch only —
#    needed for installing AUR packages via yay in the playbook)
# ---------------------------------------------------------------------------
if ! uv tool list 2>/dev/null | grep -q '^ansible '; then
  log "Installing ansible via uv tool"
  uv tool install ansible
else
  log "ansible already installed via uv tool — skipping"
fi

if [[ "$OS" == "Linux" ]] && command -v pacman >/dev/null 2>&1; then
  log "Ensuring kewlfft.aur collection is installed"
  uv tool run --from ansible ansible-galaxy collection install kewlfft.aur
fi

# ---------------------------------------------------------------------------
# 6. Clone repos to ~/repos
# ---------------------------------------------------------------------------
REPOS=(
  "Geekiac/dotfiles"
  "Geekiac/Notes"
  "Geekiac/machine-bootstrap"
)

mkdir -p ~/repos
for repo in "${REPOS[@]}"; do
  name="$(basename "$repo")"
  target=~/repos/"$name"
  if [[ -d "$target/.git" ]]; then
    log "$name already cloned — skipping"
  else
    log "Cloning $repo to $target"
    gh repo clone "$repo" "$target"
  fi
done

# ---------------------------------------------------------------------------
# 7. Run ansible playbook
# ---------------------------------------------------------------------------
PLAYBOOK=~/repos/machine-bootstrap/playbook.yml
if [[ -f "$PLAYBOOK" ]]; then
  log "Running ansible playbook: $PLAYBOOK"
  uv tool run --from ansible ansible-playbook "$PLAYBOOK" --ask-become-pass
else
  log "Playbook not found at $PLAYBOOK — skipping"
fi

log "Bootstrap complete."