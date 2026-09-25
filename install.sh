#!/bin/sh
# stellar-start — master environment setup for Stellar beginners (Linux + macOS)
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Nearx-Labs/stellar-start/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/Nearx-Labs/stellar-start/main/install.sh | sh -s -- --help
#
# What it does (core minimum):
#   1. Checks base dependencies (curl, grep, sed, tar, mktemp)
#   2. Ensures Rust toolchain >= 1.84.0 via rustup
#   3. Ensures the wasm32v1-none target
#   4. Ensures Stellar CLI (delegates to the official upstream installer for
#      latest, or installs a pinned version on --stellar-version)
#   5. Verifies everything and prints next steps (editor is manual)
#
# Design notes:
#   - POSIX sh only, no bashisms. `set -eu` for safety.
#   - Idempotent: re-running is safe and fast (skips what is already OK).
#   - Non-interactive by default so `curl | sh` works. `--yes` is accepted
#     for explicitness but not required.
#   - Windows is not supported natively: use WSL2 (see README).
set -eu

PROJECT_REPO="Nearx-Labs/stellar-start"
UPSTREAM_REPO="stellar/stellar-cli"
UPSTREAM_INSTALL_URL="https://github.com/stellar/stellar-cli/raw/main/install.sh"
MIN_RUST_VERSION="1.84.0"
WASM_TARGET="wasm32v1-none"

# --- options (defaults) ---
ASSUME_YES=false
FORCE_REINSTALL=false
USER_INSTALL=false
INSTALL_DIR=""
STELLAR_VERSION=""

# --- logging (plain technical EN with conditional ANSI colors) ---
if [ -t 1 ]; then
  C_RESET="$(printf '\033[0m')"
  C_BOLD="$(printf '\033[1m')"
  C_GREEN="$(printf '\033[32m')"
  C_BLUE="$(printf '\033[34m')"
  C_YELLOW="$(printf '\033[33m')"
  C_RED="$(printf '\033[31m')"
else
  C_RESET=""
  C_BOLD=""
  C_GREEN=""
  C_BLUE=""
  C_YELLOW=""
  C_RED=""
fi

log_info() { printf '%s[INFO]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
log_ok() { printf '%s[OK]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
log_warn() { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_error() { printf '%s[ERROR]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<EOF
stellar-start master installer (Linux + macOS)

Usage:
  curl -fsSL https://raw.githubusercontent.com/${PROJECT_REPO}/main/install.sh | sh [-s -- OPTIONS]
  ./install.sh [OPTIONS]

Options:
  -y, --yes                 Non-interactive (default behavior, kept for clarity)
      --minimal             Same as --yes (no prompts)
      --force               Reinstall Stellar CLI even if already present
      --user                Install Stellar CLI to ~/.local/bin (no sudo)
      --dir=PATH            Install Stellar CLI to a custom directory
      --stellar-version=VER Pin Stellar CLI version (e.g. 27.0.0 or v27.0.0).
                            Default: latest via upstream installer.
  -h, --help                Show this help and exit

Examples:
  sh install.sh
  sh install.sh --user
  sh install.sh --stellar-version=27.0.0 --user
  sh install.sh --force

Notes:
  - Rust >= ${MIN_RUST_VERSION} and target ${WASM_TARGET} are required for contracts.
  - Editor setup (VS Code + rust-analyzer + CodeLLDB) is manual, printed at the end.
  - Windows native is not supported. Use WSL2 + this script inside WSL.
EOF
}

# --- arg parsing ---
parse_args() {
  for arg in "$@"; do
    case "$arg" in
      -h | --help)
        usage
        exit 0
        ;;
      -y | --yes | --minimal)
        ASSUME_YES=true
        ;;
      --force)
        FORCE_REINSTALL=true
        ;;
      --user)
        USER_INSTALL=true
        INSTALL_DIR="$HOME/.local/bin"
        ;;
      --dir=*)
        INSTALL_DIR="${arg#*=}"
        if [ -z "$INSTALL_DIR" ]; then
          log_error "--dir requires a non-empty PATH"
          exit 1
        fi
        ;;
      --stellar-version=*)
        STELLAR_VERSION="${arg#*=}"
        STELLAR_VERSION="${STELLAR_VERSION#v}"
        if [ -z "$STELLAR_VERSION" ]; then
          log_error "--stellar-version requires a version like 27.0.0"
          exit 1
        fi
        ;;
      *)
        log_error "Unknown option: $arg"
        log_error "Run with --help to see available options."
        exit 1
        ;;
    esac
  done
}

# --- sudo helper ---
if [ "$(id -u)" = "0" ] || ! command_exists sudo; then
  SUDO=""
else
  SUDO="sudo "
fi

run_as_root() {
  if [ "$(id -u)" = "0" ]; then
    "$@"
    return $?
  fi
  if command_exists sudo; then
    sudo "$@"
    return $?
  fi
  log_warn "'$*' requires root, but sudo is unavailable."
  return 1
}

# --- OS / arch ---
OS=""
ARCH=""
TARGET=""

detect_platform() {
  _uname_s="$(uname -s)"
  case "$_uname_s" in
    Linux*) OS="linux" ;;
    Darwin*) OS="macos" ;;
    *)
      log_error "Unsupported operating system: $_uname_s"
      log_error "Linux and macOS only. On Windows, use WSL2 and run this script inside WSL."
      exit 1
      ;;
  esac

  _uname_m="$(uname -m)"
  case "$_uname_m" in
    x86_64 | amd64) ARCH="x86_64" ;;
    aarch64 | arm64) ARCH="aarch64" ;;
    *)
      log_error "Unsupported architecture: $_uname_m"
      exit 1
      ;;
  esac

  if [ "$OS" = "linux" ]; then
    TARGET="${ARCH}-unknown-linux-gnu"
  else
    TARGET="${ARCH}-apple-darwin"
  fi
  log_info "Detected platform: $OS ($TARGET)"
}

# --- base deps ---
check_base_deps() {
  _missing=""
  for cmd in curl grep sed tar mktemp; do
    if ! command_exists "$cmd"; then
      _missing="$_missing $cmd"
    fi
  done
  _missing="${_missing# }"
  if [ -n "$_missing" ]; then
    log_error "Missing required command(s): $_missing"
    printf '\n'
    if [ "$OS" = "macos" ]; then
      log_error "Install with Homebrew: brew install $_missing"
    elif command_exists apt-get; then
      log_error "Install on Debian/Ubuntu: ${SUDO}apt-get update && ${SUDO}apt-get install -y $_missing"
    elif command_exists dnf; then
      log_error "Install on Fedora/RHEL: ${SUDO}dnf install -y $_missing"
    elif command_exists yum; then
      log_error "Install on CentOS/RHEL: ${SUDO}yum install -y $_missing"
    elif command_exists pacman; then
      log_error "Install on Arch: ${SUDO}pacman -S --needed $_missing"
    elif command_exists zypper; then
      log_error "Install on openSUSE: ${SUDO}zypper install -y $_missing"
    else
      log_error "Install packages providing: $_missing with your distro package manager."
    fi
    exit 1
  fi
  log_ok "Base dependencies present (curl, grep, sed, tar, mktemp)"
}

# --- version compare: returns 0 if $1 >= $2 ---
version_ge() {
  # numeric compare on dot-separated versions, POSIX-safe
  _a="$1"
  _b="$2"
  _i=1
  while true; do
    _pa="$(printf '%s' "$_a" | cut -d. -f"$_i" -s)"
    _pb="$(printf '%s' "$_b" | cut -d. -f"$_i" -s)"
    [ -z "$_pa" ] && _pa=0
    [ -z "$_pb" ] && _pb=0
    # strip non-numeric suffix (e.g. 1.84.0-nightly -> 1.84.0)
    _pa="$(printf '%s' "$_pa" | sed -E 's/[^0-9].*//')"
    _pb="$(printf '%s' "$_pb" | sed -E 's/[^0-9].*//')"
    [ -z "$_pa" ] && _pa=0
    [ -z "$_pb" ] && _pb=0
    if [ "$_pa" -gt "$_pb" ]; then return 0; fi
    if [ "$_pa" -lt "$_pb" ]; then return 1; fi
    _i=$((_i + 1))
    if [ "$_i" -gt 4 ]; then return 0; fi
    if [ "$_i" -gt 3 ]; then
      case "$_a.$_b" in
        *.*.*.*) ;;
        *) return 0 ;;
      esac
    fi
  done
}

rustc_version() {
  # prints X.Y.Z from `rustc --version` ("rustc 1.84.0 (...)" )
  rustc --version 2>/dev/null | sed -E 's/[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/' || true
}

cargo_installed_version() {
  # prints X.Y.Z from `cargo --version` ("cargo 1.84.0 (...)" )
  cargo --version 2>/dev/null | sed -E 's/[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/' || true
}

ensure_cargo_env() {
  if [ -f "$HOME/.cargo/env" ]; then
    # shellcheck disable=SC1090,SC1091
    . "$HOME/.cargo/env" || true
  fi
  # rustup shims may live in ~/.cargo/bin even without env file
  case ":$PATH:" in
    *":$HOME/.cargo/bin:"*) ;;
    *)
      if [ -d "$HOME/.cargo/bin" ]; then
        PATH="$HOME/.cargo/bin:$PATH"
        export PATH
      fi
      ;;
  esac
}

install_system_build_deps() {
  # Best-effort C toolchain + TLS headers needed by rustup/cargo builds.
  # Only runs on Linux with a known package manager. Warns (never hard-fails).
  if [ "$OS" != "linux" ]; then
    return 0
  fi
  log_info "Ensuring system build dependencies (best effort)..."
  if command_exists apt-get; then
    run_as_root apt-get update || log_warn "apt-get update failed, continuing."
    run_as_root apt-get install -y curl build-essential pkg-config libssl-dev libdbus-1-dev libudev-dev \
      || log_warn "Could not install build deps via apt-get, continuing."
  elif command_exists dnf; then
    run_as_root dnf install -y curl gcc make pkgconfig openssl-devel dbus-devel systemd-devel \
      || log_warn "Could not install build deps via dnf, continuing."
  elif command_exists yum; then
    run_as_root yum install -y curl gcc make pkgconfig openssl-devel dbus-devel systemd-devel \
      || log_warn "Could not install build deps via yum, continuing."
  elif command_exists pacman; then
    run_as_root pacman -S --needed --noconfirm base-devel openssl pkg-config curl dbus systemd \
      || log_warn "Could not install build deps via pacman, continuing."
  elif command_exists zypper; then
    run_as_root zypper install -y curl gcc make pkg-config libopenssl-devel dbus-1-devel systemd-devel \
      || log_warn "Could not install build deps via zypper, continuing."
  else
    log_warn "Unknown Linux package manager; skipping system build deps."
  fi
}

install_rustup() {
  if [ "$OS" = "macos" ]; then
    if command_exists brew; then
      if ! command_exists rustup-init; then
        log_info "Installing rustup-init via Homebrew..."
        brew install rustup-init || {
          log_error "brew install rustup-init failed."
          exit 1
        }
      fi
      log_info "Running rustup-init -y..."
      rustup-init -y --default-toolchain stable --profile minimal || {
        log_error "rustup-init failed."
        exit 1
      }
    else
      log_info "Homebrew not found; installing rustup via rustup.rs..."
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal || {
        log_error "rustup installer failed."
        exit 1
      }
    fi
  else
    install_system_build_deps
    if command_exists pacman; then
      # Arch prefers the distro rustup package when available
      if ! command_exists rustup; then
        log_info "Installing rustup via pacman..."
        run_as_root pacman -S --needed --noconfirm rustup || log_warn "pacman rustup install failed, falling back to rustup.rs."
      fi
    fi
    if ! command_exists rustup; then
      log_info "Installing rustup via https://sh.rustup.rs ..."
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal || {
        log_error "rustup installer failed."
        exit 1
      }
    fi
  fi
  ensure_cargo_env
}

ensure_rust() {
  ensure_cargo_env
  if ! command_exists rustup || ! command_exists cargo || ! command_exists rustc; then
    log_info "Rust toolchain not found. Installing..."
    install_rustup
    ensure_cargo_env
  fi

  if ! command_exists rustc; then
    log_error "rustc still not found after install. Check $HOME/.cargo/bin is on PATH, then re-run."
    exit 1
  fi

  _ver="$(rustc_version)"
  if [ -n "$_ver" ] && ! version_ge "$_ver" "$MIN_RUST_VERSION"; then
    log_info "rustc $_ver is older than required ${MIN_RUST_VERSION}. Updating stable..."
    rustup update stable || {
      log_error "rustup update stable failed."
      exit 1
    }
    ensure_cargo_env
    _ver="$(rustc_version)"
    log_info "rustc is now ${_ver:-unknown}"
    if [ -n "$_ver" ] && ! version_ge "$_ver" "$MIN_RUST_VERSION"; then
      log_error "rustc $_ver still < ${MIN_RUST_VERSION}. Update manually: rustup update stable"
      exit 1
    fi
  fi

  # ensure stable is the default (harmless if already set)
  rustup default stable >/dev/null 2>&1 || log_warn "Could not set default toolchain to stable."
  log_ok "Rust toolchain OK (rustc $(rustc_version), minimum ${MIN_RUST_VERSION})"
}

ensure_target() {
  if rustup target list --installed 2>/dev/null | grep -q "^${WASM_TARGET}\$"; then
    log_ok "Target ${WASM_TARGET} already installed"
    return 0
  fi
  log_info "Installing target ${WASM_TARGET}..."
  rustup target add "${WASM_TARGET}" || {
    log_error "Failed to install target ${WASM_TARGET}."
    exit 1
  }
  log_ok "Target ${WASM_TARGET} installed"
}

# --- Stellar CLI ---
stellar_installed_version() {
  # prints X.Y.Z from first line of `stellar --version` ("stellar 27.0.0 (...)")
  stellar --version 2>/dev/null | head -n 1 | sed -E 's/[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/' || true
}

default_install_dir() {
  if [ -n "$INSTALL_DIR" ]; then
    printf '%s' "$INSTALL_DIR"
    return 0
  fi
  if [ "$USER_INSTALL" = true ]; then
    printf '%s' "$HOME/.local/bin"
    return 0
  fi
  if [ "$(id -u)" = "0" ] || [ -w "/usr/local/bin" ] 2>/dev/null; then
    printf '%s' "/usr/local/bin"
    return 0
  fi
  if command_exists sudo; then
    if sudo -n true 2>/dev/null; then
      printf '%s' "/usr/local/bin"
      return 0
    fi
  fi
  log_info "No write access to /usr/local/bin; falling back to $HOME/.local/bin" >&2
  printf '%s' "$HOME/.local/bin"
}

install_stellar_latest_via_upstream() {
  _dir="$1"
  _args=""
  if [ "$OS" = "linux" ]; then
    _args="--install-deps"
  fi
  # Pass through install location so behavior matches user flags.
  if [ "$USER_INSTALL" = true ]; then
    _args="$_args --user"
  elif [ -n "$INSTALL_DIR" ]; then
    _args="$_args --dir=$_dir"
  fi
  log_info "Installing Stellar CLI (latest) via official installer..."
  # shellcheck disable=SC2086
  if ! curl -fsSL "$UPSTREAM_INSTALL_URL" | sh -s -- $_args; then
    log_error "Official Stellar CLI installer failed."
    exit 1
  fi
}

install_stellar_pinned() {
  _ver="$1"
  _dir="$2"
  log_info "Installing Stellar CLI v${_ver} to ${_dir}..."

  # musl (e.g. Alpine) has no prebuilt glibc binary — same guard as upstream
  if [ "$OS" = "linux" ]; then
    if [ -e /lib/ld-musl-x86_64.so.1 ] || [ -e /lib/ld-musl-aarch64.so.1 ]; then
      log_error "musl libc detected (e.g. Alpine). Prebuilt Stellar CLI targets glibc."
      log_error "Use a glibc-based image (Debian/Ubuntu/Fedora) or build from source."
      exit 1
    fi
  fi

  _archive="stellar-cli-${_ver}-${TARGET}.tar.gz"
  _url="https://github.com/${UPSTREAM_REPO}/releases/download/v${_ver}/${_archive}"
  log_info "Downloading ${_url}"

  _tmp="$(mktemp -d)"
  trap 'rm -rf "$_tmp"' EXIT INT TERM HUP
  if ! curl -fsSL "$_url" -o "$_tmp/$_archive"; then
    log_error "Failed to download $_url"
    log_error "Check that v${_ver} exists: https://github.com/${UPSTREAM_REPO}/releases"
    exit 1
  fi
  (cd "$_tmp" && tar xzf "$_archive") || {
    log_error "Failed to extract $_archive"
    exit 1
  }
  if [ ! -d "$_dir" ]; then
    log_info "Creating install directory: $_dir"
    mkdir -p "$_dir"
  fi
  if [ -w "$_dir" ]; then
    mv "$_tmp/stellar" "$_dir/"
    chmod +x "$_dir/stellar"
  else
    run_as_root mv "$_tmp/stellar" "$_dir/"
    run_as_root chmod +x "$_dir/stellar"
  fi
  trap - EXIT INT TERM HUP
  rm -rf "$_tmp"
  log_ok "Stellar CLI v${_ver} installed to ${_dir}/stellar"
}

ensure_path_hint() {
  _dir="$1"
  case ":$PATH:" in
    *":$_dir:"*) ;;
    *)
      log_warn "$_dir is not in your PATH."
      printf '\n'
      log_info "Add it to your PATH by adding this line to your shell profile:"
      printf '\n  export PATH="$PATH:%s"\n\n' "$_dir"
      ;;
  esac
}

ensure_stellar_cli() {
  if command_exists stellar; then
    _cur="$(stellar_installed_version)"
    if [ -n "$STELLAR_VERSION" ]; then
      if [ "$FORCE_REINSTALL" != true ] && [ "$_cur" = "$STELLAR_VERSION" ]; then
        log_ok "Stellar CLI v${_cur} already installed (pinned version satisfied)"
        return 0
      fi
    elif [ "$FORCE_REINSTALL" != true ]; then
      log_ok "Stellar CLI already installed (v${_cur:-unknown}, $(command -v stellar))"
      return 0
    fi
  fi

  _dir="$(default_install_dir)"
  if [ ! -d "$_dir" ]; then
    log_info "Creating install directory: $_dir"
    mkdir -p "$_dir"
  fi

  if [ -n "$STELLAR_VERSION" ]; then
    install_stellar_pinned "$STELLAR_VERSION" "$_dir"
  else
    install_stellar_latest_via_upstream "$_dir"
  fi

  ensure_cargo_env
  ensure_path_hint "$_dir"

  # Include _dir in current script PATH to allow immediate validation
  case ":$PATH:" in
    *":$_dir:"*) ;;
    *) PATH="$_dir:$PATH"; export PATH ;;
  esac

  if ! command_exists stellar; then
    if [ -x "$_dir/stellar" ]; then
      log_warn "stellar installed to $_dir/stellar but failed to execute."
    else
      log_error "stellar still not found after install."
      exit 1
    fi
  else
    log_ok "Stellar CLI OK (v$(stellar_installed_version))"
  fi
}

print_summary() {
  printf '\n========================================\n'
  log_ok "Stellar environment ready."
  printf '  rustc:   %s\n' "$(rustc_version || echo missing)"
  printf '  cargo:   %s\n' "$(cargo_installed_version || echo missing)"
  printf '  target:  %s\n' "$WASM_TARGET"
  printf '  stellar: %s\n' "$(stellar_installed_version || echo missing)"
  printf '========================================\n'
}

print_next_steps() {
  _shell="$(basename "${SHELL:-bash}")"
  printf '\nNext Steps:\n'
  printf '  1. Shell completion (detected: %s):\n' "$_shell"
  case "$_shell" in
    zsh)  printf '     source <(stellar completion --shell zsh)\n' ;;
    fish) printf '     stellar completion --shell fish | source\n' ;;
    *)    printf '     source <(stellar completion --shell bash)\n' ;;
  esac
  printf '  2. Editor setup (VS Code):\n'
  printf '     Install extensions: rust-analyzer, vadimcn.vscode-lldb\n'
  printf '  3. Getting started:\n'
  printf '     stellar --help\n'
  printf '     Docs: https://developers.stellar.org/docs/tools/cli/stellar-cli.md\n'
  printf '     Repo: https://github.com/%s\n' "$PROJECT_REPO"
}

main() {
  parse_args "$@"
  log_info "stellar-start setup (https://github.com/${PROJECT_REPO})"
  detect_platform
  check_base_deps
  ensure_rust
  ensure_target
  ensure_stellar_cli
  print_summary
  print_next_steps
}

main "$@"
