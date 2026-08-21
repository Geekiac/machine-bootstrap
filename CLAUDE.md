# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Bootstraps Arch and macOS machines from nothing to a working dev environment. Two files do all the work:

- **`bootstrap.sh`** — a shell script for a fresh machine with nothing on it. Installs Xcode CLT (macOS), Homebrew or pacman, Claude Code, `uv`, `gh`, and Ansible, then hands off to `playbook.yml`.
- **`playbook.yml`** — an Ansible playbook that installs the standard toolset (Homebrew formulae/casks on macOS, pacman/AUR on Arch) and applies dotfiles from `Geekiac/dotfiles` via chezmoi.

Both are idempotent — designed to be re-run safely any time, on either OS.

## No build/test/lint commands

There is no build step, test suite, or linter in this repo. "Development" here means editing the shell script and the playbook directly, then validating by running them (see below). When making changes, match the idempotency and OS-branching patterns already in each file rather than introducing new ones.

## Running/validating changes

```bash
bash bootstrap.sh                                                       # full run
uv tool run --from ansible ansible-playbook playbook.yml --ask-become-pass   # playbook only, if ansible/kewlfft.aur already installed
```

There's no CI and no sandbox for a "fresh machine" — changes are generally validated by re-running on an already-bootstrapped machine (where most steps should no-op) or reasoning carefully about the fresh-machine path, since a bad change can't be safely tested from scratch without an actual clean VM/container per OS.

## Architecture notes

- **Step numbering is shared vocabulary** between `bootstrap.sh`'s header comment, its inline `log` messages, and the `## What it does` table in `README.md`. If you add, remove, or reorder a step, update all three places.
- **OS branching**: `bootstrap.sh` branches on `uname -s` (`Darwin` vs `Linux`+`pacman`); `playbook.yml` branches on Ansible facts (`ansible_facts['os_family'] == "Darwin"` / `ansible_facts['distribution'] == "Archlinux"`). Every macOS-only or Arch-only task needs its `when` guard.
- **`kewlfft.aur` is installed unconditionally on both OSes** (bootstrap.sh step 5), even though the playbook only *uses* it for Arch's AUR tasks. Ansible resolves every task's module up front regardless of `when` conditions, so the playbook fails to parse on macOS without it. Don't gate this install to Arch only.
- **Prefer trusting exit codes over parsing command output.** `playbook.yml`'s Homebrew tasks deliberately use `ansible.builtin.command` instead of `community.general.homebrew`/`homebrew_cask`, because those modules parse brew's text output to judge success and misreport "already installed" as a failure against current Homebrew's output format. Follow this pattern for other commands with unstable/parseable output.
- **Two `sudo`/interactive touchpoints exist outside Ansible's own `--ask-become-pass`**: `xcode-select --install` pops a macOS GUI dialog (bootstrap.sh step 0), and building `yay` from source calls `sudo` internally partway through `makepkg` (playbook.yml). Both only trigger on a genuinely fresh machine and require someone at the keyboard; subsequent runs skip them and run non-interactively. Keep this property when touching those steps.
- **VS Code is deliberately the MS-branded build on both OSes**: `visual-studio-code` cask on macOS, `visual-studio-code-bin` from the AUR on Arch — not Arch's official-repo `code` (open-source vscode-oss, Open VSX only). Don't "fix" this to use the repo package.
- **Arch's fortune package is `fortune-mod`**, not `fortune` — the name differs from the macOS Homebrew formula and from what you'd guess. Same pattern for the Fira Code Nerd Font: `ttf-firacode-nerd` on Arch vs `font-fira-code-nerd-font` on macOS.
- **The `nvm` Homebrew formula doesn't create its own working directory** — its caveat says to create `~/.nvm` manually. `playbook.yml` does this via an unconditional `ansible.builtin.file` task (no `when` guard) rather than gating it to macOS, since it's harmless on Arch too. Same "just do it on both OSes" reasoning as the `kewlfft.aur` install above.
- **chezmoi lifecycle**: `init` only runs once (guarded by checking whether `~/.local/share/chezmoi` exists), `apply` runs every invocation. Keep this split if touching those tasks.
- **No secrets live in this repo.** Anything sensitive (API keys, Ansible Vault-encrypted vars) belongs in the `dotfiles` repo or a password manager, not here.

## Repo cross-references

`bootstrap.sh` clones `Geekiac/dotfiles`, `Geekiac/Notes`, and `Geekiac/machine-bootstrap` itself into `~/repos`, then runs `playbook.yml` from the cloned copy — not from wherever `bootstrap.sh` itself was originally invoked. Keep this in mind if changing paths or the clone step: edits to a locally-checked-out `machine-bootstrap` won't affect a fresh bootstrap run until pushed, since the script re-clones from GitHub.
