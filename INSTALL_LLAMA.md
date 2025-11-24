# Llama.cpp on NVIDIA Jetson Nano (4GB)

This guide provides a robust method for installing hardware-accelerated `llama.cpp` on the original Jetson Nano 4GB (JetPack 4.6.6 / CUDA 10.2).

**Why this guide?**
Modern `llama.cpp` releases generally require newer compilers and CUDA versions than JetPack 4 supports. This guide targets a specific "Golden Commit" ( **Build 2440** ) that retains legacy CUDA support while enabling modern GGUF models. It includes critical patches for missing NEON intrinsics on the Nano's older GCC environment.

## Prerequisites

* **Device:** Jetson Nano 4GB (B01 or equivalent)
* **OS:** JetPack 4.6.1 (L4T R32.7.1)
* **Storage:** NVMe SSD highly recommended (SD cards are slow for model loading).
* **Swap:** Ensure at least 4GB of SWAP is active.

## 1. System Setup & Compiler Upgrade

The default GCC 7 is too old. We must install GCC 8 without breaking the system default.

```
# Update system
sudo apt-get update
sudo apt-get install -y git build-essential

# Install GCC-8 and G++-8
sudo apt-get install -y gcc-8 g++-8

# Verify versions (should be 8.x)
gcc-8 --version
g++-8 --version
```

## 2. Configure CUDA Paths

JetPack 4 often separates CUDA 10.2 libraries from the standard path. Fix this link for the compiler:

```
# Create symlink if missing
if [ ! -d "/usr/local/cuda" ]; then
    sudo ln -sf /usr/local/cuda-10.2 /usr/local/cuda
fi

# Export paths (Add these to your ~/.bashrc for permanence)
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
```

## 3. Clone the Compatible Version

We use  **Build 2440 (Commit `12247f4c6`)** , the last known version to robustly support the `LLAMA_CUBLAS` legacy flag.

```
git clone [https://github.com/ggerganov/llama.cpp](https://github.com/ggerganov/llama.cpp)
cd llama.cpp

# Checkout the specific compatible commit
git checkout -f b2440
```

## 4. Patch Missing NEON Intrinsics

The GCC 8 compiler on JetPack 4 lacks specific NEON vector load functions (`vld1q_s8_x4`). You must manually patch `ggml-quants.c`.

1. Open the file:
   ```
   nano ggml-quants.c
   ```
2. Automated option (recommended): use the included `insert_neon_patch.sh` script to apply the patch safely.

   - The script will locate `ggml-quants.c` (or accept its path), create a timestamped backup, detect if the patch is already present, and insert the compatibility code in a safe location.

   - Example: auto-discover and patch in the current repository
     ```bash
     ./insert_neon_patch.sh
     ```

   - Example: patch a specific file path
     ```bash
     ./insert_neon_patch.sh path/to/ggml-quants.c
     ```

   - The script prints the backup file path (e.g. `ggml-quants.c.bak.163...`) so you can review and revert if needed. Review the modified file before rebuilding.

3. Manual option (alternative): if you prefer to patch by hand, edit `ggml-quants.c` and insert the following block inside an `#if defined(__ARM_NEON)` guard (or after the `#include` section):

   ```c
   /* --- START PATCH FOR JETSON NANO / GCC 8 --- */
   #if defined(__ARM_NEON) && !defined(vld1q_s8_x4)

   // Fix for missing vld1q_s8_x4
   static inline int8x16x4_t vld1q_s8_x4(const int8_t *ptr) {
       int8x16x4_t out;
       out.val[0] = vld1q_s8(ptr);
       out.val[1] = vld1q_s8(ptr + 16);
       out.val[2] = vld1q_s8(ptr + 32);
       out.val[3] = vld1q_s8(ptr + 48);
       return out;
   }

   // Fix for missing vld1q_u8_x4
   static inline uint8x16x4_t vld1q_u8_x4(const uint8_t *ptr) {
       uint8x16x4_t out;
       out.val[0] = vld1q_u8(ptr);
       out.val[1] = vld1q_u8(ptr + 16);
       out.val[2] = vld1q_u8(ptr + 32);
       out.val[3] = vld1q_u8(ptr + 48);
       return out;
   }

   // Fix for missing vld1q_s16_x2
   static inline int16x8x2_t vld1q_s16_x2(const int16_t *ptr) {
       int16x8x2_t out;
       out.val[0] = vld1q_s16(ptr);
       out.val[1] = vld1q_s16(ptr + 8);
       return out;
   }
   #endif
   /* --- END PATCH --- */
   ```

4. Save and exit (`Ctrl+O`, `Enter`, `Ctrl+X`) if editing manually.

5. Verify the patch was applied (automated script echoes the backup; manual check example):

   ```bash
   # Check for the patch marker
   grep -n "START PATCH FOR JETSON NANO" ggml-quants.c || true
   ```

6. Rebuild as instructed in Step 5 after confirming the patch is present.

## 5. Compile with GPU Support

Use the legacy `LLAMA_CUBLAS` flag and target the Nano's Maxwell GPU (`sm_53`).

```
# Clean previous builds
make clean

# Compile
# CC/CXX: Force GCC-8
# LLAMA_CUBLAS=1: Legacy GPU support flag
# CUDA_DOCKER_ARCH=sm_53: Jetson Nano Architecture
CC=gcc-8 CXX=g++-8 LLAMA_CUBLAS=1 CUDA_DOCKER_ARCH=sm_53 make -j$(nproc)
```

## 6. Run Performance Optimizations

Before running the model, free up RAM and maximize clock speeds.

1. **Disable GUI (Headless Mode):** Saves ~800MB RAM.
   ```
   sudo systemctl set-default multi-user.target
   sudo reboot
   ```
2. **Maximize Clocks (Run after every reboot):**
   ```
   sudo jetson_clocks
   ```

## 7. Running the Server

Dowload the llama model in folder

```bash
bash
wget https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf \
-P ../models
```

Use `tinyllama-1.1b` (Q4_K_M) for best performance. Larger models (7B) will be extremely slow or OOM.

```
# Ensure libraries are found
export LD_LIBRARY_PATH=/usr/local/cuda-10.2/lib64:$LD_LIBRARY_PATH

# Start Server
# -ngl 100: Offload 100% of layers to GPU
# -c 2048: Context window
# -b 512: Batch size (Higher causes OOM on Nano)
./server \
  -m tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf \
  -ngl 100 \
  -c 2048 \
  -b 512 \
  --host 0.0.0.0 \
  --port 8080
```

## Troubleshooting

* **"fatal error: ggml-common.h: No such file or directory"** : This means you pasted the patch code into a new file and tried to compile it directly, or the include path is wrong. **Do not create a separate `patch.c` file.** You must paste the patch code directly into `ggml-quants.c` as instructed in Step 4.
* **"error while loading shared libraries: libcublas..."** : You forgot to export `LD_LIBRARY_PATH`.
* **"BLAS = 0" in logs** : The model is running on CPU. Recheck compilation flags and ensure `-ngl 100` is passed.
* **System freezes** : You ran out of RAM. Reduce context `-c` or ensure GUI is disabled.
