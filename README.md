# stellar-start

One-liner master setup for Stellar smart-contract development on a beginner machine (Linux + macOS).

## Quick install

```sh
curl -fsSL https://raw.githubusercontent.com/Nearx-Labs/stellar-start/main/install.sh | sh
```

With options:

```sh
curl -fsSL https://raw.githubusercontent.com/Nearx-Labs/stellar-start/main/install.sh | sh -s -- --help
curl -fsSL https://raw.githubusercontent.com/Nearx-Labs/stellar-start/main/install.sh | sh -s -- --user
curl -fsSL https://raw.githubusercontent.com/Nearx-Labs/stellar-start/main/install.sh | sh -s -- --stellar-version=27.0.0 --user
```

Pinned version:

```sh
curl -fsSL https://raw.githubusercontent.com/Nearx-Labs/stellar-start/v1.0.0/install.sh | sh
```

## What the script does (core minimum)

1. Checks base tools: `curl`, `grep`, `sed`, `tar`, `mktemp`.
2. Ensures Rust toolchain `>= 1.84.0` via `rustup` (installs or `rustup update stable` if needed).
3. Ensures the `wasm32v1-none` compilation target (`rustup target add wasm32v1-none`).
4. Ensures Stellar CLI:
   - default (latest): delegates to the official installer at `stellar/stellar-cli` (`install.sh`).
   - `--stellar-version=X`: installs that release directly from GitHub.
   - skips reinstall if already present (use `--force` to reinstall).
5. Verifies `rustc`, `cargo`, target, and `stellar --version`, checks `PATH`, and prints editor + completion next steps.

Idempotent: safe to re-run.

## Options

| Flag | Description |
| ---- | ----------- |
| `-y, --yes, --minimal` | Non-interactive (default behavior, kept for clarity) |
| `--force` | Reinstall Stellar CLI even if already present |
| `--user` | Install Stellar CLI to `~/.local/bin` (no sudo) |
| `--dir=PATH` | Install Stellar CLI to a custom directory |
| `--stellar-version=VER` | Pin version, e.g. `27.0.0` or `v27.0.0` (default: latest) |
| `-h, --help` | Show help |

## Editor setup (manual)

The script does not install editors. Do this once manually:

1. [Visual Studio Code](https://code.visualstudio.com)
2. [Rust Analyzer](https://marketplace.visualstudio.com/items?itemName=rust-lang.rust-analyzer) for Rust support
3. [CodeLLDB](https://marketplace.visualstudio.com/items?itemName=vadimcn.vscode-lldb) for step-through debugging

Rust editor docs: https://www.rust-lang.org/tools

## Shell completion (recommended)

```sh
# Bash (current session)
source <(stellar completion --shell bash)
# persist:
echo "source <(stellar completion --shell bash)" >> ~/.bashrc

# ZSH
source <(stellar completion --shell zsh)
echo "source <(stellar completion --shell zsh)" >> ~/.zshrc

# fish
stellar completion --shell fish | source
echo "stellar completion --shell fish | source" >> ~/.config/fish/config.fish

# PowerShell
stellar completion --shell powershell | Out-String | Invoke-Expression

# Elvish
source (stellar completion --shell elvish)
```

Full CLI reference: https://developers.stellar.org/docs/tools/cli/stellar-cli.md

## Requirements

- Linux or macOS (`x86_64` / `arm64`).
- Windows native is **not** supported. Use [WSL2](https://learn.microsoft.com/en-us/windows/wsl/install), then run this script inside WSL.
- glibc-based Linux. musl (e.g. Alpine) has no prebuilt Stellar CLI binary — use Debian/Ubuntu/Fedora or build from source.
- Internet access to `sh.rustup.rs` and `github.com`.

## Troubleshooting

- `Missing required command(s)`: install with the command the script prints (apt/dnf/yum/pacman/zypper/brew).
- `rustc still < 1.84.0`: run `rustup update stable && rustup target add wasm32v1-none`.
- `stellar ... not on PATH`: add the install dir shown by the script, e.g. `export PATH="$PATH:$HOME/.local/bin"`, then restart the terminal.
- Emojis show as `?` on Windows: use Windows Terminal; functionality is unaffected.
- Stellar CLI issues: https://github.com/stellar/stellar-cli/issues/new/choose

## Local development

```sh
chmod +x install.sh
shellcheck install.sh
./install.sh --help
./install.sh --user
```

## Security

Prefer `curl -fsSL` over plain `curl | sh`. Pin to a tag (`/v1.0.0/install.sh`) for reproducible onboarding. Review the script before piping to a shell on shared machines.
