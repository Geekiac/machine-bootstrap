# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Bootstraps Arch and macOS machines from nothing to a working dev environment. Two files do all the work:

- **`bootstrap.sh`** — a shell script for a fresh machine with nothing on it. Installs Xcode CLT (macOS), Homebrew or pacman, `uv`, `gh`, and Ansible, then hands off to `playbook.yml`.
- **`playbook.yml`** — an Ansible playbook that installs Claude Code first (deliberately — so it's available to help debug if any later step fails), then the rest of the standard toolset (Homebrew formulae/casks on macOS, pacman/AUR on Arch), and applies dotfiles from `Geekiac/dotfiles` via chezmoi.

Both are idempotent — designed to be re-run safely any time, on either OS.

## No build/test/lint commands

There is no build step, test suite, or linter in this repo. "Development" here means editing the shell script and the playbook directly, then validating by running them (see below). When making changes, match the idempotency and OS-branching patterns already in each file rather than introducing new ones.

## Running/validating changes

```bash
bash bootstrap.sh                                                       # full run
uv tool run --from ansible-core ansible-playbook playbook.yml --ask-become-pass   # playbook only, if ansible-core/collections already installed
```

There's no CI and no sandbox for a "fresh machine" — changes are generally validated by re-running on an already-bootstrapped machine (where most steps should no-op) or reasoning carefully about the fresh-machine path, since a bad change can't be safely tested from scratch without an actual clean VM/container per OS.

## Architecture notes

- **Step numbering is shared vocabulary** between `bootstrap.sh`'s header comment, its inline `log` messages, and the `## What it does` table in `README.md`. If you add, remove, or reorder a step, update all three places.
- **OS branching**: `bootstrap.sh` branches on `uname -s` (`Darwin` vs `Linux`+`pacman`); `playbook.yml` branches on Ansible facts (`ansible_facts['os_family'] == "Darwin"` / `ansible_facts['distribution'] == "Archlinux"`). Every macOS-only or Arch-only task needs its `when` guard.
- **`community.general` and `kewlfft.aur` are installed unconditionally on both OSes** (bootstrap.sh step 4, via `ansible-galaxy` against the lean `ansible-core` package rather than the bundled `ansible` metapackage), even though the playbook only *uses* them for Arch's pacman/AUR tasks. Ansible resolves every task's module up front regardless of `when` conditions, so the playbook fails to parse on macOS without them. Don't gate this install to Arch only.
- **Prefer trusting exit codes over parsing command output.** `playbook.yml`'s Homebrew tasks deliberately use `ansible.builtin.command` instead of `community.general.homebrew`/`homebrew_cask`, because those modules parse brew's text output to judge success and misreport "already installed" as a failure against current Homebrew's output format. Follow this pattern for other commands with unstable/parseable output.
- **Claude Code's install task is deliberately the first task in `playbook.yml`**, ahead of even the macOS/Arch package sections, so it's already on the machine to help debug anything that fails later in the same run. It's OS-agnostic (same `curl -fsSL https://claude.ai/install.sh | bash`, no `when` guard) and checks `ansible.builtin.stat` on `~/.local/bin/claude` directly rather than `command -v claude`/`which claude` — Ansible's command/shell modules don't source `.bashrc`/`.zshrc`, so a chezmoi-managed `PATH` addition doesn't apply in that exec context. Follow the same explicit-path-check reasoning for any other installer that lands outside a system bin directory already on the default `PATH`.
- **Three `sudo`/interactive touchpoints exist outside Ansible's own `--ask-become-pass`**: `xcode-select --install` pops a macOS GUI dialog (bootstrap.sh step 0), building `yay` from source calls `sudo` internally partway through `makepkg` (playbook.yml), and `yay` itself calls `sudo pacman -U` internally to install whatever it just built (playbook.yml's AUR task). The first two only trigger on a genuinely fresh machine; the third re-triggers any time a *new* package is added to `aur_packages`, since `kewlfft.aur` only invokes yay for packages that aren't already installed — it fails with "sudo: a terminal is required to read the password" if run non-interactively, or blocks on a password prompt otherwise. All three require someone at the keyboard; already-installed packages and subsequent runs skip them and run non-interactively. Keep this property when touching those steps. When adding a new AUR package, expect to `yay -S <package>` by hand once before/after the playbook run.
- **VS Code is deliberately the MS-branded build on both OSes**: `visual-studio-code` cask on macOS, `visual-studio-code-bin` from the AUR on Arch — not Arch's official-repo `code` (open-source vscode-oss, Open VSX only). Don't "fix" this to use the repo package.
- **Arch's fortune package is `fortune-mod`**, not `fortune` — the name differs from the macOS Homebrew formula and from what you'd guess. Same pattern for the Fira Code Nerd Font: `ttf-firacode-nerd` on Arch vs `font-fira-code-nerd-font` on macOS.
- **The `nvm` Homebrew formula doesn't create its own working directory** — its caveat says to create `~/.nvm` manually. `playbook.yml` does this via an unconditional `ansible.builtin.file` task (no `when` guard) rather than gating it to macOS, since it's harmless on Arch too. Same "just do it on both OSes" reasoning as the `kewlfft.aur` install above.
- **chezmoi lifecycle**: `init` only runs once (guarded by checking whether `~/.local/share/chezmoi` exists), `apply` runs every invocation. Keep this split if touching those tasks.
- **No secrets live in this repo.** Anything sensitive (API keys, Ansible Vault-encrypted vars) belongs in the `dotfiles` repo or a password manager, not here.

## Repo cross-references

`bootstrap.sh` clones `Geekiac/dotfiles`, `Geekiac/Notes`, and `Geekiac/machine-bootstrap` itself into `~/repos`, then runs `playbook.yml` from the cloned copy — not from wherever `bootstrap.sh` itself was originally invoked. Keep this in mind if changing paths or the clone step: edits to a locally-checked-out `machine-bootstrap` won't affect a fresh bootstrap run until pushed, since the script re-clones from GitHub.
