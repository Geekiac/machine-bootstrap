# machine-bootstrap

For bootstrapping Arch and macOS machines.

`bootstrap.sh` gets a fresh machine from nothing to a working dev
environment: Xcode CLT (macOS), Homebrew or pacman, Claude Code, `uv`,
`gh`, and Ansible. It then hands off to `playbook.yml`, which installs
the standard toolset and applies dotfiles via chezmoi.

Both files are idempotent — safe to re-run any time, on either machine.

## Installation

Review-first (recommended default):

```bash
curl -fsSL https://raw.githubusercontent.com/Geekiac/machine-bootstrap/main/bootstrap.sh -o bootstrap.sh
less bootstrap.sh      # eyeball it before running
bash bootstrap.sh
```

Direct pipe, no local file left behind:

```bash
curl -fsSL https://raw.githubusercontent.com/Geekiac/machine-bootstrap/main/bootstrap.sh | bash
```

No git or Homebrew is required beforehand — `curl` alone is enough to
fetch the script on a completely fresh machine.

## kewlfft.aur collection

The playbook installs Chrome, Obsidian, and VS Code (MS build) from
the AUR via `yay`, using the `kewlfft.aur` Ansible collection. Unlike
`community.general` (bundled with the `ansible` PyPI package), this
one isn't bundled — `bootstrap.sh` installs it automatically as part
of step 5, on both OSes. It's only *used* on Arch, but Ansible resolves
every task's module up front regardless of `when` conditions, so the
playbook fails to parse on macOS without it too — hence installing it
unconditionally rather than gating it to Arch.

## What it does

**`bootstrap.sh`**

Before the numbered steps, it ensures `~/.local/bin` is on `PATH` for
the session (uv tool installs and Claude Code's native installer both
land executables there) — added only if missing, session-only, not
written to any shell rc file. That's left to the chezmoi-managed
dotfiles, same as Homebrew's `shellenv` in step 1.

| Step | Action |
|---|---|
| 0 | Install Xcode Command Line Tools (macOS only) |
| 1 | Install Homebrew (macOS only) |
| 2 | Install Claude Code |
| 3 | Install `uv` and `gh` — brew on macOS, pacman on Arch |
| 4 | `gh auth login` |
| 5 | Install Ansible via `uv tool`, plus `kewlfft.aur` collection (both OSes) |
| 6 | Clone `Notes` and `machine-bootstrap` to `~/repos` (`dotfiles` lives only in chezmoi's own clone, `~/.local/share/chezmoi` — see step 7) |
| 7 | Run `playbook.yml` |

**`playbook.yml`**

- macOS: installs CLI tools via Homebrew formulae, GUI apps/fonts via
  Homebrew casks
- Arch: installs official-repo packages via pacman, bootstraps `yay`
  from source if missing, then installs Chrome, Obsidian, and VS Code
  (MS build) from the AUR
- Applies dotfiles from `Geekiac/dotfiles` via chezmoi (`init` once,
  `apply` every run). chezmoi's own clone at `~/.local/share/chezmoi`
  (or `chezmoi source-path`) is the only copy of the repo on disk —
  it isn't also cloned to `~/repos/dotfiles`
- Clones Doom Emacs to `~/.config/emacs` and runs `doom install`, once
  only (both are idempotent/safe to re-run, but re-syncing packages on
  every run would be slow for no benefit) — runs after chezmoi so
  `DOOMDIR` (`~/.config/doom`, chezmoi-managed) is already in place

## First run isn't fully unattended

A couple of steps need you at the keyboard the first time only:

- **macOS**: `xcode-select --install` opens a GUI dialog — the script
  waits for it, but you need to click through it.
- **Arch**: pacman tasks prompt via Ansible's `--ask-become-pass`, but
  building `yay` from source also calls `sudo` internally partway
  through `makepkg` — a second, separate password prompt outside
  Ansible's control.
- **macOS**: the Mac App Store apps task needs an Apple ID already
  signed in via the App Store app's GUI — `mas` can't do this itself,
  and can't prompt for it either. If nothing's signed in yet, that
  task fails; sign in through the App Store app once, then re-run.

Subsequent runs on an already-bootstrapped machine skip all of this
and run non-interactively.

## Notes

- `code` (Arch's official-repo VS Code) is deliberately not installed
  — `visual-studio-code-bin` from the AUR is used instead, to match
  the Marketplace-enabled build the Homebrew cask installs on macOS.
- Arch's fortune package is named `fortune-mod`, not `fortune`.
- Arch's Fira Code Nerd Font package is named `ttf-firacode-nerd`, not
  `ttf-fira-code` — matches the macOS cask's switch from plain
  `font-fira-code` to `font-fira-code-nerd-font`.
- No secrets live in this repo. Anything sensitive (API keys, Ansible
  Vault-encrypted vars) belongs in `dotfiles` or a password manager,
  not here.