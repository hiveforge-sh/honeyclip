## GPU Runtime Detection and Configuration
##
## Detects available GPU backends (CUDA on Linux, CoreML on macOS) and provides
## runtime configuration for ONNX Runtime execution providers with CPU fallback.

type
  GpuBackend* = enum
    ## GPU acceleration backend
    CPU = "cpu"
    CUDA = "cuda"      # Linux + NVIDIA GPU
    CoreML = "coreml"  # macOS 10.15+ (all Apple hardware)

  GpuRuntime* = object
    ## Runtime GPU configuration
    backend*: GpuBackend
    available*: bool
    deviceName*: string

when defined(windows):
  # Windows ML features are stubbed (LTO build issues with ML libraries)
  proc detectGpu*(): GpuRuntime =
    ## Windows always returns CPU backend
    result = GpuRuntime(
      backend: CPU,
      available: false,
      deviceName: "CPU"
    )

  proc logBackend*(runtime: GpuRuntime) =
    ## Log which backend is active
    echo "[gpu] Using backend: ", runtime.backend, " (", runtime.deviceName, ")"

else:
  # Linux/macOS implementation
  import std/os

  when defined(linux):
    proc checkCudaAvailable(): bool =
      ## Check if CUDA runtime is available via library existence
      ## Searches common CUDA library paths without hard-linking
      const cudaPaths = [
        "/usr/local/cuda/lib64/libcudart.so",
        "/usr/lib/x86_64-linux-gnu/libcudart.so",
        "/usr/local/cuda/lib64/libnvcuda.so",
        "/usr/lib/x86_64-linux-gnu/libnvcuda.so"
      ]

      for path in cudaPaths:
        if fileExists(path):
          return true

      return false

  when defined(macosx):
    proc checkCoreMLAvailable(): bool =
      ## CoreML is always available on macOS 10.15+ (Catalina or later)
      ## We only target recent macOS versions
      result = true

  proc detectGpu*(): GpuRuntime =
    ## Detect available GPU and return runtime configuration
    ## Order of preference: CUDA (Linux) -> CoreML (macOS) -> CPU (fallback)

    when defined(linux):
      if checkCudaAvailable():
        return GpuRuntime(
          backend: CUDA,
          available: true,
          deviceName: "NVIDIA GPU (CUDA)"
        )

    when defined(macosx):
      if checkCoreMLAvailable():
        return GpuRuntime(
          backend: CoreML,
          available: true,
          deviceName: "Apple Neural Engine"
        )

    # Fallback to CPU
    return GpuRuntime(
      backend: CPU,
      available: false,
      deviceName: "CPU"
    )

  proc logBackend*(runtime: GpuRuntime) =
    ## Log which backend is active
    echo "[gpu] Using backend: ", runtime.backend, " (", runtime.deviceName, ")"
