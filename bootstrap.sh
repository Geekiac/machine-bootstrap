#!/usr/bin/env bash
#
# bootstrap.sh — idempotent machine bootstrap
#
# Safe to re-run: every step checks current state before acting.
#
# Steps:
#   0. Install Xcode Command Line Tools (macOS only, if missing)
#   1. Install Homebrew (macOS only, if missing)
#   2. Install uv, gh — brew on macOS, pacman on Arch (if missing)
#   3. gh auth login + wire gh credentials into git (if not already authenticated)
#   4. Install ansible via uv tool, plus kewlfft.aur collection (both OSes)
#   5. gh clone Notes and machine-bootstrap to ~/repos (dotfiles is
#      cloned separately by chezmoi in step 6, not to ~/repos)
#   6. run ansible playbook (which installs Claude Code first, then the
#      rest of the standard toolset)
#
set -euo pipefail

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }

OS="$(uname -s)"

# ---------------------------------------------------------------------------
# ~/.local/bin on PATH — uv tool installs (step 4) land executables
# here. Only added if missing, and only for this script's own session.
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
# 1. Homebrew (macOS only — Arch uses pacman, see step 2)
# ---------------------------------------------------------------------------
if [[ "$OS" == "Darwin" ]]; then
  if ! command -v brew >/dev/null 2>&1; then
    log "Homebrew not found — installing from https://brew.sh"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/tty

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
# 2. uv and gh — brew on macOS, pacman on Arch
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
# 3. gh auth login, then wire gh's credentials into plain git
#
# gh's own commands (gh repo clone, step 5) authenticate themselves and
# don't need this. But plain `git clone` — which is what chezmoi init
# uses under the hood — has no idea gh is authenticated at all, and
# will prompt for a username/password on any private repo without it.
# ---------------------------------------------------------------------------
if ! gh auth status >/dev/null 2>&1; then
  log "gh not authenticated — starting login flow"
  gh auth login < /dev/tty
else
  log "gh already authenticated — skipping"
fi

log "Wiring gh credentials into git (gh auth setup-git)"
gh auth setup-git

# ---------------------------------------------------------------------------
# 4. ansible via uv tool, plus the kewlfft.aur collection
#
# Installed unconditionally, on both OSes — even though it's only used
# by Arch-specific tasks in the playbook, Ansible resolves every task's
# module up front regardless of its `when` condition, so the playbook
# fails to parse on macOS without this present too.
# ---------------------------------------------------------------------------
if ! uv tool list 2>/dev/null | grep -q '^ansible '; then
  log "Installing ansible via uv tool"
  uv tool install ansible
else
  log "ansible already installed via uv tool — skipping"
fi

log "Ensuring kewlfft.aur collection is installed"
uv tool run --from ansible ansible-galaxy collection install kewlfft.aur

# ---------------------------------------------------------------------------
# 5. Clone repos to ~/repos
#
# dotfiles isn't cloned here — chezmoi (via playbook.yml) clones it into
# its own source directory instead (~/.local/share/chezmoi, aka
# `chezmoi source-path`), and that's its only copy on disk.
# ---------------------------------------------------------------------------
REPOS=(
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
# 6. Run ansible playbook
# ---------------------------------------------------------------------------
PLAYBOOK=~/repos/machine-bootstrap/playbook.yml
if [[ -f "$PLAYBOOK" ]]; then
  log "Running ansible playbook: $PLAYBOOK"
  uv tool run --from ansible ansible-playbook "$PLAYBOOK" --ask-become-pass
else
  log "Playbook not found at $PLAYBOOK — skipping"
fi

log "Bootstrap complete."