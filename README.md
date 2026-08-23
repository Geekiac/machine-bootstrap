# machine-bootstrap

For bootstrapping Arch and macOS machines.

`bootstrap.sh` gets a fresh machine from nothing to a working dev
environment: Xcode CLT (macOS), Homebrew or pacman, `uv`, `gh`, `yay`
and AUR packages (Arch), and Ansible. It then hands off to
`playbook.yml`, which installs Claude Code first (so it's available to
help if anything later fails), then the rest of the standard toolset,
and applies dotfiles via chezmoi.

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

## AUR packages on Arch

`bootstrap.sh` (step 3), not `playbook.yml`, builds `yay` from source
if missing and installs Chrome and VS Code (MS build) from the AUR
through it. This is deliberate: `yay` calls `sudo` internally, both to
build itself and to install whatever it just built, and that inner
`sudo` call has no TTY to read a password from when invoked through
Ansible's command module — even though `ansible-playbook
--ask-become-pass` is interactive, that password only covers Ansible's
own privilege escalation, not `yay`'s separate call. Running it in
`bootstrap.sh`'s own interactive shell instead sidesteps that
entirely. (Obsidian isn't among these AUR packages — see below.)

The playbook still uses `community.general` for the `pacman` module.
`bootstrap.sh` installs Ansible as the lean `ansible-core` PyPI
package (not the full `ansible` metapackage) and installs
`community.general` explicitly via `ansible-galaxy` as part of step 5,
on both OSes — it's only *used* on Arch, but Ansible resolves every
task's module up front regardless of `when` conditions, so the
playbook fails to parse on macOS without it too, hence installing it
unconditionally rather than gating to Arch.

## Obsidian on Arch

Obsidian isn't in Arch's official repos, only the AUR — but rather
than add another entry to `bootstrap.sh`'s AUR package list for a GUI
app that publishes its own Linux build directly, the playbook
downloads Obsidian's own official AppImage straight from GitHub and
drops it in `~/.local/bin`, the same "installer lands a binary on
`PATH`" pattern used for Claude Code and `herdr`. This needs `fuse2`
(`libfuse.so.2`) to run, which isn't installed by Arch by default —
it's in `pacman_packages` alongside it. On macOS, Obsidian still
installs normally via the Homebrew cask.

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
| 3 | Install `yay` and AUR packages — Chrome, VS Code (MS build) (Arch only) |
| 4 | `gh auth login` |
| 5 | Install `ansible-core` via `uv tool`, plus the `community.general` collection (both OSes) |
| 6 | Clone `Notes` and `machine-bootstrap` to `~/repos` (`dotfiles` lives only in chezmoi's own clone, `~/.local/share/chezmoi` — see step 7) |
| 7 | Run `playbook.yml` (installs Claude Code first, then the rest of the standard toolset) |

**`playbook.yml`**

- Installs Claude Code first, before anything else — if a later step
  fails, Claude Code is already on the machine to help debug it
- Installs `herdr` via its own install script, on both OSes — not a
  Homebrew formula or AUR package; upstream doesn't publish an AUR
  package itself (the third-party `herdr-bin` is community-maintained),
  so the official installer is used instead
- Installs [`claude-usage`](https://github.com/phuryn/claude-usage) via
  `uv tool install`, on both OSes — a local dashboard/CLI for Claude
  Code token usage, cost estimates, and session history
- macOS: installs CLI tools via Homebrew formulae, GUI apps/fonts via
  Homebrew casks
- Arch: installs official-repo packages via pacman; Obsidian installs
  from its own AppImage (see "Obsidian on Arch" above) — `yay` and AUR
  packages (Chrome, VS Code MS build) are installed earlier, by
  `bootstrap.sh` (see "AUR packages on Arch" above)
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
- **Arch**: `bootstrap.sh` (step 3) builds `yay` from source if
  missing, which calls `sudo` internally partway through `makepkg` — a
  password prompt outside Ansible's `--ask-become-pass` entirely, since
  this step runs before the playbook does. This, and every `yay -S`
  call for AUR packages, needs a real terminal — that's why it lives in
  `bootstrap.sh` and not `playbook.yml` (see "AUR packages on Arch"
  above).
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