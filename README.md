# machine-bootstrap

For bootstrapping Arch and macOS machines.

`bootstrap.sh` gets a fresh machine from nothing to a working dev
environment: Xcode CLT (macOS), Homebrew or pacman, Claude Code, `uv`,
`gh`, and Ansible. It then hands off to `playbook.yml`, which installs
the standard toolset and applies dotfiles via chezmoi.

Both files are idempotent — safe to re-run any time, on either machine.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/Geekiac/machine-bootstrap/main/bootstrap.sh -o bootstrap.sh
less bootstrap.sh      # eyeball it before running
bash bootstrap.sh
```

No git or Homebrew is required beforehand — `curl` alone is enough to
fetch the script on a completely fresh machine.

## kewlfft.aur collection

The playbook installs Chrome and VS Code (MS build) from the AUR via
`yay`, using the `kewlfft.aur` Ansible collection. Unlike
`community.general` (bundled with the `ansible` PyPI package), this
one isn't bundled — `bootstrap.sh` installs it automatically as part
of step 5, on Linux only (it's not needed on macOS).

## What it does

**`bootstrap.sh`**

| Step | Action |
|---|---|
| 0 | Install Xcode Command Line Tools (macOS only) |
| 1 | Install Homebrew (macOS only) |
| 2 | Install Claude Code |
| 3 | Install `uv` and `gh` — brew on macOS, pacman on Arch |
| 4 | `gh auth login` |
| 5 | Install Ansible via `uv tool`, plus `kewlfft.aur` collection (Arch only) |
| 6 | Clone `dotfiles`, `Notes`, and `machine-bootstrap` to `~/repos` |
| 7 | Run `playbook.yml` |

**`playbook.yml`**

- macOS: installs CLI tools via Homebrew formulae, GUI apps/fonts via
  Homebrew casks
- Arch: installs official-repo packages via pacman, bootstraps `yay`
  from source if missing, then installs Chrome and VS Code (MS build)
  from the AUR
- Applies dotfiles from `Geekiac/dotfiles` via chezmoi (`init` once,
  `apply` every run)

## First run isn't fully unattended

A couple of steps need you at the keyboard the first time only:

- **macOS**: `xcode-select --install` opens a GUI dialog — the script
  waits for it, but you need to click through it.
- **Arch**: pacman tasks prompt via Ansible's `--ask-become-pass`, but
  building `yay` from source also calls `sudo` internally partway
  through `makepkg` — a second, separate password prompt outside
  Ansible's control.

Subsequent runs on an already-bootstrapped machine skip all of this
and run non-interactively.

## Notes

- `code` (Arch's official-repo VS Code) is deliberately not installed
  — `visual-studio-code-bin` from the AUR is used instead, to match
  the Marketplace-enabled build the Homebrew cask installs on macOS.
- Arch's fortune package is named `fortune-mod`, not `fortune`.
- No secrets live in this repo. Anything sensitive (API keys, Ansible
  Vault-encrypted vars) belongs in `dotfiles` or a password manager,
  not here.