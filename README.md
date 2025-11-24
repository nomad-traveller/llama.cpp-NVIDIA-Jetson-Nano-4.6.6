# llama.cpp-on NVIDIA Jetson Nano 4GB (JetPack 4.6.6)

This repository provides a tested setup to build and run `llama.cpp` with GPU acceleration on the Jetson Nano (JetPack 4 / CUDA 10.2). It includes helper scripts and documentation tailored to the Nano's older toolchain and limited RAM.

What this repo provides
- A focused `INSTALL_LLAMA.md` with step-by-step instructions to prepare the system, apply necessary patches (including NEON fixes), build with `LLAMA_CUBLAS`, and run or serve models.
- Helper scripts in the repo root:
    - `update_os.sh` — optional system-update and package-prep helper (review before running).
    - `insert_neon_patch.sh` — safely inserts a NEON-compatibility patch into `ggml-quants.c` and creates a backup.

Quick pointers
- Read `INSTALL_LLAMA.md` for the full, canonical install and build instructions.
- Use `insert_neon_patch.sh` to apply the NEON patch automatically; a manual patch is also described in `INSTALL_LLAMA.md`.
- The recommended build uses `CC=gcc-8 CXX=g++-8 LLAMA_CUBLAS=1 CUDA_DOCKER_ARCH=sm_53`. On the Nano prefer limited parallelism (e.g. `-j2`) to avoid OOM during compile.

If you want a quick example or the full commands, see `INSTALL_LLAMA.md` (this README intentionally stays high-level to avoid duplication).
