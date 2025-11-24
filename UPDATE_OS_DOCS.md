# update_os.sh — Documentation for customers

This document explains the purpose, behavior, and customization points for `update_os.sh` so customers can modify it safely and confidently.

**Location:** `/home/user/remote/update_os.sh`

**Purpose:**
- Perform system update/cleanup (apt update/upgrade/autoremove/autoclean)
- Install required packages (apt)
- Ensure `jetson-stats` (`jtop`) is available (pip3)
- Detect and configure CUDA 10.2 (symlink and environment variables)
- Increase swap space (idempotent)

Overview of design
- The script is modular and implemented with functions. This makes it easy to find and change behavior.
- It supports `--dry-run` to print actions instead of executing them.
- Behaviors are idempotent where possible: package installs are skipped for already-installed packages, `/swapfile` is checked for size before recreating, and lines added to `~/.bashrc` are appended only if missing.

Quick usage

- Dry-run (safe):

```bash
bash /home/user/remote/update_os.sh --dry-run
```

- Real run (requires sudo for system changes):

```bash
sudo bash /home/user/remote/update_os.sh
```

- Show help:

```bash
bash /home/user/remote/update_os.sh --help
```

Command-line flags
- `--no-swap` — Skip increasing the system swap (useful if you manage swap another way).
- `--no-gcc` — Present for compatibility; currently ignored (script will print a message).
- `--no-update` — Skip running apt update/upgrade/autoremove/autoclean.
- `--dry-run` — Print the commands the script would run instead of executing them.
- `-h`, `--help` — Print usage help.
 - `--install-vscode` — (Default: enabled) Install Visual Studio Code if not already present. The script now installs VS Code by default; see the "VS Code installation" section below for details.
 - `--vscode-version <ver>` — Specify VS Code version (default: `1.85.2`). Use `latest` to download the latest stable build.

Function map and where to modify
- `parse_args()`
  - Parses the script flags. If you want to add new flags, add them here and document them in the help message in `usage()`.

- `run()`
  - Wrapper used for commands that change the system. It prints actions under `--dry-run` and executes otherwise. Prefer using `run` for commands that affect system state, so dry-run works consistently.
  - Note: `run` executes the command by invoking it as a function `"$@"`. When passing complex shell pipelines you must wrap them in `bash -c "..."` and call via `run bash -c "..."`.

- `increase_swapspace()`
  - Idempotent swap creation (defaults to 8GB). It:
    - Skips when `--no-swap` is passed.
    - If `/swapfile` exists and is >= 8GB, it does nothing.
    - Otherwise recreates `/swapfile` with desired size and adds it to `/etc/fstab`.
  - Customization points:
    - Change `local desired_gb=8` at the top of the function to alter the swap size.
    - If you want a different swap path, adjust `/swapfile` occurrences.

- `ensure_updates()`
  - Runs apt update/upgrade/autoremove/autoclean unless `--no-update` is passed.
  - If you want to modify which apt operations run, edit this function.

- `install_required_packages()`
  - Contains `REQUIRED_PACKAGES=(cuda-nvcc-10-2 curl git python3-pip nano cmake libcurl4-openssl-dev)`.
  - The function checks each package with `dpkg -s` and only installs missing packages.
  - To add or remove packages, edit the `REQUIRED_PACKAGES` array.
  - Note: Some package names (like `cuda-nvcc-10-2`) are distribution-specific. If your customers use different package names or repositories, document and change these package names accordingly.

- `ensure_jetson_stats()`
  - Checks for the `jetson-stats` pip3 package or the `jtop` command, and installs `jetson-stats` via `pip3` if needed.
  - If you prefer to install via a system package or a distro-managed method, change this function.

- `check_cuda_presence()`
  - Returns success if CUDA 10.2 appears to be present (either as apt packages or `nvcc` reports release `10.2`). This will cause the script to create a symlink and add environment variables.

- `ensure_cuda_symlink()`
  - Creates `/usr/local/cuda` symlink pointing to `/usr/local/cuda-10.2` if appropriate.
  - If `/usr/local/cuda` already exists the function skips creating the symlink and prints which condition prevented it.

- `configure_bashrc()`
  - Adds three lines to `~/.bashrc` if they're not already present:
    - `export CUDA_HOME=/usr/local/cuda`
    - `export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda/lib64`
    - `export PATH=$PATH:/usr/local/cuda/bin`
  - If you prefer system-wide environment variables for services, consider adding equivalent files under `/etc/profile.d/` instead of editing `~/.bashrc`.

Testing, linting, and verification
- Dry-run
  - Always test changes with `--dry-run` to see what will run before executing any system changes.

- Linting
  - `shellcheck` is used to catch common shell issues. Example:

```bash
sudo apt install -y shellcheck
shellcheck /home/user/remote/update_os.sh
```

- Post-run checks
  - Verify swap: `swapon --show` and `free -h`.
  - Verify CUDA symlink: `ls -l /usr/local/cuda` and `nvcc --version`.
  - Verify `jtop`: run `sudo jtop` (if you installed `jetson-stats`).
  - Verify VS Code: run `code --version` or `which code` to confirm the `code` command is present.

VS Code installation (idempotent and now default)
 - The script includes an `ensure_vscode()` function that installs Visual Studio Code by default (the variable `INSTALL_VSCODE` is enabled). If you do not want VS Code installed by default, you can set `INSTALL_VSCODE=0` in the script or run with an opt-out flag (if added).
 - Idempotent behavior: `ensure_vscode()` checks multiple indicators to avoid reinstalling VS Code if it's already present:
   - `code` command in `PATH` (preferred check)
   - Debian package `code` present (`dpkg -s code`)
   - Installed as a snap (`snap list code`)
 - Installation method: the script downloads the VS Code Debian package for `arm64` using the same URL pattern as `installVSCode.sh` and installs it with `sudo apt install -y /tmp/vscode-linux-deb.arm64.deb`.
 - Customization points:
   - To change the default version, set `VSCODE_VERSION` at the top of `update_os.sh` or pass `--vscode-version <ver>` at runtime.
   - If you need a different architecture (x86_64, etc.), modify the download URL in `ensure_vscode()` to match your platform.
 - Example (dry-run, install latest):

```bash
bash /home/user/remote/update_os.sh --dry-run --vscode-version latest
```

Customization examples

1) Change swap size to 16GB

Edit the `increase_swapspace()` function and set:
```bash
local desired_gb=16
```

2) Add a package to the apt list

Edit the `REQUIRED_PACKAGES` array near `install_required_packages()`:
```bash
REQUIRED_PACKAGES=(cuda-nvcc-10-2 curl git python3-pip nano cmake libcurl4-openssl-dev your-package)
```

3) Skip CUDA environment modifications

If you want to skip CUDA symlink and env changes unconditionally, modify `main()` near the bottom to omit the `check_cuda_presence` conditional, or replace `if check_cuda_presence; then ...` with a different condition.

4) Use a different pip command or venv

If you want to install Python packages into a virtualenv instead of global `pip3`, change `ensure_jetson_stats()` to activate the venv and run `pip install` there.

Troubleshooting
- `shellcheck` warnings: run `shellcheck` and follow the suggestions. The script has already been adjusted to avoid several common warnings (shebang on first line, avoiding `eval`, etc.).

- `apt-get install` hangs or requires interactive input: make sure `DEBIAN_FRONTEND=noninteractive` is set when running in automated contexts, e.g.:

```bash
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y package
```

- `fallocate` not supported on target filesystem: some filesystems (e.g., older formats or certain network filesystems) may not support `fallocate`. The current script uses `fallocate` to create `/swapfile`. If you encounter errors, replace that step with `dd` method:

```bash
sudo dd if=/dev/zero of=/swapfile bs=1M count=8192
```

- Permissions or sudo failures: ensure the user running the script has `sudo` privileges, or run the full script via `sudo`.

Security considerations
- The script appends lines to `~/.bashrc` and modifies `/etc/fstab`. Verify these modifications are acceptable in your deployment context.
- Installing third-party Python packages globally (`pip3 install`) can affect system packages. Prefer installing into virtual environments when possible.

Version control and committing
- After making changes, commit with a clear message:

```bash
git add update_os.sh UPDATE_OS_DOCS.md
git commit -m "Refactor update_os.sh; add documentation UPDATE_OS_DOCS.md"
```

Support and further changes
- If your customers want to adapt this script for a different Debian/Ubuntu release or a different Jetson/CUDA version, the main areas to change are:
  - `REQUIRED_PACKAGES` (package names)
  - CUDA detection strings in `check_cuda_presence()`
  - Symlink target in `ensure_cuda_symlink()`
  - Swap size in `increase_swapspace()`

Contact
- If you'd like, I can also:
  - Add inline function comments in `update_os.sh` for each function.
  - Create separate example variants (e.g., `update_os_no_cuda.sh`, `update_os_minimal.sh`).
  - Convert the script into a more formal installer (with subcommands and logging).

---

Document created on: 2025-11-23
