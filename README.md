# machine-bootstrap

For bootstrapping Arch and macOS machines.

`bootstrap.sh` gets a fresh machine from nothing to a working dev
environment: Xcode CLT (macOS), Homebrew or pacman, `uv`, `gh`, and
Ansible. It then hands off to `playbook.yml`, which installs Claude
Code first (so it's available to help if anything later fails), then
the rest of the standard toolset, and applies dotfiles via chezmoi.

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

The playbook installs Chrome and VS Code (MS build) from the AUR via
`yay`, using the `kewlfft.aur` Ansible collection, and uses
`community.general` for pacman. (Obsidian isn't among them — see
below.) `bootstrap.sh` installs Ansible as the lean `ansible-core`
PyPI package (not the full `ansible` metapackage) and installs both
collections explicitly via `ansible-galaxy` as part of step 4, on
both OSes. They're only *used* on Arch, but Ansible resolves every
task's module up front regardless of `when` conditions, so the
playbook fails to parse on macOS without them too — hence installing
them unconditionally rather than gating to Arch.

## Obsidian on Arch

Obsidian isn't in Arch's official repos, only the AUR — but rather
than route a GUI app through `yay`'s first-time sudo/tty wall (see
below), the playbook downloads Obsidian's own official AppImage
straight from GitHub and drops it in `~/.local/bin`, the same
"installer lands a binary on `PATH`" pattern used for Claude Code and
`herdr`. This needs `fuse2` (`libfuse.so.2`) to run, which isn't
installed by Arch by default — it's in `pacman_packages` alongside it.
On macOS, Obsidian still installs normally via the Homebrew cask.

## What it does

**`bootstrap.sh`**

Before the numbered steps, it ensures `~/.local/bin` is on `PATH` for
the session (uv tool installs land executables there) — added only if
missing, session-only, not written to any shell rc file. That's left
to the chezmoi-managed dotfiles, same as Homebrew's `shellenv` in
step 1.

| Step | Action |
|---|---|
| 0 | Install Xcode Command Line Tools (macOS only) |
| 1 | Install Homebrew (macOS only) |
| 2 | Install `uv` and `gh` — brew on macOS, pacman on Arch |
| 3 | `gh auth login` |
| 4 | Install `ansible-core` via `uv tool`, plus `community.general` and `kewlfft.aur` collections (both OSes) |
| 5 | Clone `Notes` and `machine-bootstrap` to `~/repos` (`dotfiles` lives only in chezmoi's own clone, `~/.local/share/chezmoi` — see step 6) |
| 6 | Run `playbook.yml` (installs Claude Code first, then the rest of the standard toolset) |

**`playbook.yml`**

- Installs Claude Code first, before anything else — if a later step
  fails, Claude Code is already on the machine to help debug it
- Installs `herdr` via its own install script, on both OSes — not a
  Homebrew formula or AUR package, since upstream doesn't publish an
  AUR package and going through `yay` needed an interactive terminal
  for every newly-added AUR package (see the "First run isn't fully
  unattended" note below)
- macOS: installs CLI tools via Homebrew formulae, GUI apps/fonts via
  Homebrew casks
- Arch: installs official-repo packages via pacman, bootstraps `yay`
  from source if missing, then installs Chrome and VS Code (MS build)
  from the AUR; Obsidian installs from its own AppImage instead (see
  "Obsidian on Arch" above)
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
and run non-interactively — with one exception: **Arch**, adding a
*new* package to `aur_packages` re-triggers the same problem as the
`yay` build above, every time, not just on a fresh machine. `yay`
itself calls `sudo pacman -U` internally to install whatever it just
built, and `kewlfft.aur` only invokes `yay` for packages that aren't
already installed — so it fails with "sudo: a terminal is required to
read the password" if run non-interactively, or blocks on a password
prompt otherwise. Run `yay -S <new-package>` by hand once, then re-run
the playbook — it'll see the package already installed and skip.

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