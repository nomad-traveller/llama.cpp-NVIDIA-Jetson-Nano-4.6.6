# llama.cpp-on NVIDIA Jetson Nano 4GB (JetPack 4.6.6)
This guide provides a robust method to install hardware-accelerated llama.cpp on the original Jetson Nano 4GB.

The Problem: The Jetson Nano is stuck on JetPack 4 (Ubuntu 18.04 / CUDA 10.2), while modern llama.cpp versions require newer compilers and CUDA 11+. Standard installation attempts usually fail with "CPU only" builds or compiler errors.

The Solution: This guide uses a specific compatible commit of llama.cpp, upgrades the compiler to GCC-8, and applies the correct legacy build flags to force GPU acceleration on the Nano's Maxwell GPU.

## Prerequisites
* Hardware: Jetson Nano 4GB (B01 or older).
* OS: JetPack 4.6.1 (L4T R32.7.1) recommended.
* Swap: Ensure you have at least 4GB of SWAP file active (JetPack usually creates this by default).

## Step 1: Install Dependencies & GCC-8
The default GCC 7 on JetPack 4 is too old to compile modern GGUF-compatible code. We must install GCC 8.
```bash
sudo apt-get update
sudo apt-get install -y git build-essential

# Install GCC-8 and G++-8
sudo apt-get install -y gcc-8 g++-8

# Verify installation (Should print version 8.x)
gcc-8 --version
```
## Step 2: Fix CUDA Paths
JetPack 4 often leaves the CUDA paths unconnected for standard Makefiles. We create a symlink to ensure the compiler finds the GPU libraries.
```bash
# Check if /usr/local/cuda exists. If not, link it to cuda-10.2
if [ ! -d "/usr/local/cuda" ]; then
    sudo ln -s /usr/local/cuda-10.2 /usr/local/cuda
fi

# Verify nvcc is accessible
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
nvcc --version
```
## Step 3: Clone llama.cpp (Build 2440)
We use Build 2440 (Commit 12247f4c6). This version is the "sweet spot"—it supports modern GGUF models but still supports the LLAMA_CUBLAS build system compatible with CUDA 10.2.
```bash
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp

# Checkout the specific compatible commit (March 2024)
git checkout 12247f4c6
```
## Step 4: Compile with GPU Acceleration
This is the critical step. We must use LLAMA_CUBLAS=1 (not LLAMA_CUDA), explicitly define the Nano's GPU architecture (sm_53), and force the use of GCC-8.
```bash
# Clean any previous build attempts
make clean

# Compile
# - LLAMA_CUBLAS=1: Activates GPU support for older CUDA versions
# - CUDA_DOCKER_ARCH=sm_53: Targets the Jetson Nano (Tegra X1) GPU
# - -j2: Limits cores to prevent RAM exhaustion during compile
CC=gcc-8 CXX=g++-8 LLAMA_CUBLAS=1 CUDA_DOCKER_ARCH=sm_53 make -j2
```
Note: Compilation takes about 10-15 minutes.

## Step 5: Verify GPU Linking
Once finished, check if the binary is actually linked to the NVIDIA libraries.
```bash
ldd ./main | grep cuda
```
Success: You should see lines pointing to /usr/local/cuda-10.2/lib64/libcublas.so....

Failure: If there is no output, the GPU libraries were not linked. Check Step 2 and rebuild.

## Step 6: Download a Model (TinyLlama)
The Jetson Nano has limited RAM (4GB shared). We recommend TinyLlama-1.1B (Quantized Q4_K_M), which uses ~800MB of RAM, leaving plenty of room for the system.
```bash
wget https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf
```
## Step 7: Run the Model
To run with GPU acceleration, we use -ngl 100 (number of GPU layers = 100) to offload the entire model to the GPU.
```bash
# Run in interactive chat mode
./main -m tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf -ngl 100 -c 2048 --color -i -r "User:" -p 'User: Hello!\nAssistant:'
```
Performance Tip: Before running, set the Jetson to max performance mode to prevent lag:
```bash
sudo jetson_clocks
```
Bonus: Running as a Python/Web Server
You can also compile the server to use the Jetson as an API host (compatible with OpenAI libraries).
```bash
# Compile the server binary
CC=gcc-8 CXX=g++-8 LLAMA_CUBLAS=1 CUDA_DOCKER_ARCH=sm_53 make server -j2

# Run the server on port 8080
./server -m tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf -ngl 100 -c 2048 --host 0.0.0.0 --port 8080
```
You can now access the chat interface at http://<YOUR_JETSON_IP>:8080.
