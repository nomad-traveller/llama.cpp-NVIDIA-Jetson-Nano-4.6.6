#!/usr/bin/env bash

O_SWAP=0
DRY_RUN=0
NO_UPDATE=0
SWAP_SIZE=8
INSTALL_VSCODE=1
VSCODE_VERSION=1.85.2

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --swap-size <GB> Change swap size in GB (default: 8)
  --no-swap       Skip swap creation steps
  --no-gcc        Skip GCC installation
  --install-vscode  Install Visual Studio Code (Deb from Microsoft)
  --vscode-version <ver>  Specify VS Code version (default: 1.85.2)
  --no-update     Skip apt update/upgrade/clean
  --dry-run       Print commands instead of executing
  -h, --help      Show this help
EOF
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "DRY-RUN: $*"
  else
    echo "+ $*"
    "$@"
  fi
}

command_exists() { command -v "$1" >/dev/null 2>&1; }
dpkg_installed() { dpkg -s "$1" >/dev/null 2>&1; }
pip3_package_installed() { pip3 show "$1" >/dev/null 2>&1; }

# Logging helpers
log_info()  { printf "[INFO] %s\n" "$*"; }
log_warn()  { printf "[WARN] %s\n" "$*"; }
log_error() { printf "[ERROR] %s\n" "$*"; }

# Safe command runner. Accepts a single string command for complex pipelines,
# or arrays can still be executed by calling `run_array "$@"`.
run_cmd() {
  local cmd="$*"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "DRY-RUN: $cmd"
  else
    echo "+ $cmd"
    bash -c "$cmd"
  fi
}

# Execute command from array args (avoids invoking shell when not needed).
run_array() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "DRY-RUN: $*"
  else
    echo "+ $*"
    "$@"
  fi
}

increase_swapspace() {
  local desired_gb="$SWAP_SIZE"
  if [ "$O_SWAP" -eq 1 ]; then
    echo "Skipping swap modification (--no-swap)"
    return 0
  fi

  # If /swapfile exists, check size in GB and skip if already big enough
  if [ -f /swapfile ]; then
    current_bytes=$(stat -c%s /swapfile 2>/dev/null || echo 0)
    current_gb=$((current_bytes / 1024 / 1024 / 1024))
    if [ "$current_gb" -ge "$desired_gb" ]; then
      echo "Existing /swapfile is ${current_gb}GB (>= ${desired_gb}GB) — no change needed"
      return 0
    else
      echo "Existing /swapfile is ${current_gb}GB (< ${desired_gb}GB) — recreating"
      run sudo swapoff -a
      run sudo rm -f /swapfile
    fi
  fi

  echo "Increasing swap space to ${desired_gb}GB..."
  run sudo swapoff -a || true
  run sudo fallocate -l "${desired_gb}G" /swapfile
  run sudo chmod 600 /swapfile
  run sudo mkswap /swapfile
  run sudo swapon /swapfile
  if ! grep -q '/swapfile' /etc/fstab; then
    run bash -c "echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab"
  fi
  echo "Swap space ensured (${desired_gb}GB)"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-swap) O_SWAP=1; shift ;;
      --no-gcc) echo "--no-gcc is ignored in this script"; shift ;;
      --swap-size) shift; SWAP_SIZE="$1"; shift ;;
      --install-vscode) INSTALL_VSCODE=1; shift ;;
      --vscode-version) shift; VSCODE_VERSION="$1"; shift ;;
      --no-update) NO_UPDATE=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown arg: $1"; usage; exit 1 ;;
    esac
  done
}

ensure_updates() {
  if [ "$NO_UPDATE" -ne 1 ]; then
    run sudo apt update
    run sudo apt upgrade -y
    run sudo apt autoremove -y
    run sudo apt autoclean
  else
    echo "Skipping system update/upgrade (--no-update)"
  fi
}

REQUIRED_PACKAGES=(cuda-nvcc-10-2 curl git python3-pip nano cmake libcurl4-openssl-dev \
                   build-essential gcc-8 g++-8 ccache libcublas-dev)

gather_missing_packages() {
  log_info "Checking required packages and collecting missing ones..."
  MISSING_PACKAGES=()
  for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if dpkg_installed "$pkg"; then
      log_info "- $pkg: already installed"
    else
      log_warn "- $pkg: NOT installed"
      MISSING_PACKAGES+=("$pkg")
    fi
  done
}

install_missing_packages() {
  if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    log_info "Installing missing packages: ${MISSING_PACKAGES[*]}"
    # Use run_cmd for safety in case package names contain special characters
    run_cmd sudo apt-get install -y "${MISSING_PACKAGES[@]}"
  else
    log_info "All required packages are already installed."
  fi
}

ensure_vscode() {
  log_info "Ensuring Visual Studio Code is installed..."
  if [ "$INSTALL_VSCODE" -ne 1 ]; then
    log_info "VS Code installation not requested; skipping"
    return 0
  fi

  # Detect whether VS Code is already installed using multiple heuristics:
  # - `code` command in PATH
  # - Debian package named `code` installed via dpkg
  # - installed as a snap (snap list)
  if command_exists code || dpkg_installed code || (command_exists snap && snap list code >/dev/null 2>&1); then
    log_info "Visual Studio Code already installed; skipping installation"
    return 0
  fi

  local ver="${VSCODE_VERSION:-latest}"
  local out="/tmp/vscode-linux-deb.arm64.deb"
  log_info "Downloading VS Code version: $ver"
  run_cmd wget -N -O "$out" "https://update.code.visualstudio.com/${ver}/linux-deb-arm64/stable"

  log_info "Installing VS Code from $out"
  # apt install supports local debs
  run_cmd sudo apt install -y "$out"
  log_info "VS Code install step completed"
}

ensure_jetson_stats() {
  echo "Ensuring jetson-stats (jtop) is available..."
  if pip3_package_installed jetson-stats; then
    echo "jetson-stats (pip) already installed"
  elif command_exists jtop; then
    echo "jtop command already available"
  else
    run sudo -H pip3 install -U jetson-stats
  fi
  echo "jetson-stats available. Run 'sudo jtop' to monitor the device." 
}

check_cuda_presence() {
  CUDA_PRESENT=0
  if dpkg_installed cuda-nvcc-10-2 || dpkg_installed cuda-10-2; then
    CUDA_PRESENT=1
  fi
  if [ $CUDA_PRESENT -eq 0 ] && command_exists nvcc; then
    if nvcc --version 2>/dev/null | grep -q "release 10.2"; then
      CUDA_PRESENT=1
    fi
  fi
  if [ $CUDA_PRESENT -eq 1 ]; then
    return 0
  else
    return 1
  fi
}

ensure_cuda_symlink() {
  if [ -d "/usr/local/cuda-10.2" ] && [ ! -e "/usr/local/cuda" ]; then
    echo "Creating /usr/local/cuda -> /usr/local/cuda-10.2 symlink"
    run sudo ln -s /usr/local/cuda-10.2 /usr/local/cuda
  else
    if [ -e "/usr/local/cuda" ]; then
      echo "/usr/local/cuda already exists; skipping symlink"
    else
      echo "/usr/local/cuda-10.2 not installed; cannot create symlink"
    fi
  fi
}

add_line_if_missing() {
  local line="$1" file="$2"
  if ! grep -Fqx "$line" "$file" 2>/dev/null; then
    echo "Adding to $file: $line"
    echo "$line" >> "$file"
    return 0
  else
    echo "Already present in $file: $line"
    return 1
  fi
}

configure_bashrc() {
  echo "Verifying CUDA installation and configuring environment variables..."
  CUDA_PREFIX=/usr/local/cuda
  CUDA_BIN="$CUDA_PREFIX/bin"
  CUDA_LIB="$CUDA_PREFIX/lib64"
  BASHRC="$HOME/.bashrc"
  BASHRC_CHANGED=0

  add_line_if_missing "export CUDA_HOME=$CUDA_PREFIX" "$BASHRC" && BASHRC_CHANGED=1
  add_line_if_missing "export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:$CUDA_LIB" "$BASHRC" && BASHRC_CHANGED=1
  add_line_if_missing "export PATH=\$PATH:$CUDA_BIN" "$BASHRC" && BASHRC_CHANGED=1

  if [ "$BASHRC_CHANGED" -eq 1 ]; then
    # shellcheck disable=SC1090
    source "$BASHRC"
  fi
}

main() {
  parse_args "$@"
  increase_swapspace
  ensure_updates
  gather_missing_packages
  install_missing_packages
  ensure_jetson_stats
  ensure_vscode
  if check_cuda_presence; then
    ensure_cuda_symlink
    configure_bashrc
  else
    echo "CUDA 10.2 not detected; skipping CUDA symlink and env configuration."
  fi
}

main "$@"
