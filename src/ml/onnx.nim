## ONNX Runtime FFI wrapper
##
## Provides type-safe interface to ONNX Runtime C API for ML model inference.
## Handles environment setup, session management, and tensor operations.

import std/strformat

type
  OrtError* = object of CatchableError
    ## Exception raised when ONNX Runtime operation fails
    code*: int

  OrtEnv* = object
    ## ONNX Runtime environment (global context)
    handle: pointer

  OrtSession* = object
    ## Loaded ONNX model session
    handle: pointer

  OrtValue* = object
    ## Tensor value (input/output)
    handle: pointer

  OrtMemoryInfo* = object
    ## Memory allocation info
    handle: pointer

when defined(windows):
  # Stub implementations for Windows (ML libraries have LTO build issues)
  # TODO: Rebuild ONNX Runtime without LTO for Windows support

  proc initOrtEnv*(name: string = "honeyclip", logLevel: int = 3): OrtEnv =
    raise newException(OrtError, "ONNX Runtime not available on Windows (LTO build issue)")

  proc `=destroy`*(env: var OrtEnv) =
    discard

  proc loadModel*(env: OrtEnv, modelPath: string): OrtSession =
    raise newException(OrtError, "ONNX Runtime not available on Windows (LTO build issue)")

  proc `=destroy`*(session: var OrtSession) =
    discard

  proc createTensor*(data: ptr float32, shape: openArray[int64],
                     elemType: int = 1): OrtValue =
    raise newException(OrtError, "ONNX Runtime not available on Windows (LTO build issue)")

  proc `=destroy`*(value: var OrtValue) =
    discard

  proc run*(session: OrtSession, inputs: openArray[OrtValue],
            inputNames: openArray[string],
            outputNames: openArray[string]): seq[OrtValue] =
    raise newException(OrtError, "ONNX Runtime not available on Windows (LTO build issue)")

  proc getTensorData*[T](value: OrtValue): ptr UncheckedArray[T] =
    raise newException(OrtError, "ONNX Runtime not available on Windows (LTO build issue)")

else:
  # Full implementation for Linux/macOS

  # C API types from onnxruntime_c_wrapper.h
  type
    OrtStatus {.importc, header: "onnxruntime_c_wrapper.h".} = object
    OrtApiBase {.importc, header: "onnxruntime_c_wrapper.h".} = object
      GetApi*: proc(version: uint32): ptr OrtApi {.cdecl.}
    OrtApi {.importc, header: "onnxruntime_c_wrapper.h".} = object
      CreateEnv*: proc(logLevel: cint, logid: cstring, env: ptr pointer): ptr OrtStatus {.cdecl.}
      ReleaseEnv*: proc(env: pointer) {.cdecl.}
      CreateSession*: proc(env: pointer, modelPath: cstring, options: pointer,
                           session: ptr pointer): ptr OrtStatus {.cdecl.}
      ReleaseSession*: proc(session: pointer) {.cdecl.}
      CreateCpuMemoryInfo*: proc(allocType: cint, memType: cint,
                                 info: ptr pointer): ptr OrtStatus {.cdecl.}
      ReleaseMemoryInfo*: proc(info: pointer) {.cdecl.}
      CreateTensorWithDataAsOrtValue*: proc(
        info: pointer, data: pointer, dataLen: csize_t,
        shape: ptr int64, shapeLen: csize_t, elemType: cint,
        value: ptr pointer): ptr OrtStatus {.cdecl.}
      ReleaseValue*: proc(value: pointer) {.cdecl.}
      Run*: proc(session: pointer, runOptions: pointer,
                 inputNames: ptr cstring, inputs: ptr pointer, inputCount: csize_t,
                 outputNames: ptr cstring, outputCount: csize_t,
                 outputs: ptr pointer): ptr OrtStatus {.cdecl.}
      GetTensorMutableData*: proc(value: pointer, data: ptr pointer): ptr OrtStatus {.cdecl.}
      GetErrorMessage*: proc(status: ptr OrtStatus): cstring {.cdecl.}
      ReleaseStatus*: proc(status: ptr OrtStatus) {.cdecl.}

  proc OrtGetApiBase(): ptr OrtApiBase {.importc, header: "onnxruntime_c_wrapper.h".}

  # Global API pointer
  var g_ort: ptr OrtApi = nil

  proc getApi(): ptr OrtApi =
    ## Get ONNX Runtime API function table
    if g_ort == nil:
      let base = OrtGetApiBase()
      g_ort = base.GetApi(14)  # ORT API version 14 (ONNX Runtime 1.14+)
    return g_ort

  proc checkOrt(status: ptr OrtStatus) =
    ## Check OrtStatus and raise exception if error occurred
    if status != nil:
      let api = getApi()
      let msg = $api.GetErrorMessage(status)
      api.ReleaseStatus(status)
      raise newException(OrtError, "ONNX Runtime error: " & msg)

  proc initOrtEnv*(name: string = "honeyclip", logLevel: int = 3): OrtEnv =
    ## Initialize ONNX Runtime environment (do this once at startup)
    let api = getApi()
    var handle: pointer
    let status = api.CreateEnv(logLevel.cint, name.cstring, addr handle)
    checkOrt(status)
    result.handle = handle

  proc `=destroy`*(env: var OrtEnv) =
    ## Automatic cleanup of OrtEnv
    if env.handle != nil:
      let api = getApi()
      api.ReleaseEnv(env.handle)
      env.handle = nil

  proc loadModel*(env: OrtEnv, modelPath: string): OrtSession =
    ## Load ONNX model from file path
    let api = getApi()
    var handle: pointer
    let status = api.CreateSession(env.handle, modelPath.cstring, nil, addr handle)
    checkOrt(status)
    result.handle = handle

  proc `=destroy`*(session: var OrtSession) =
    ## Automatic cleanup of OrtSession
    if session.handle != nil:
      let api = getApi()
      api.ReleaseSession(session.handle)
      session.handle = nil

  proc createTensor*(data: ptr float32, shape: openArray[int64],
                     elemType: int = 1): OrtValue =
    ## Create input tensor from float32 array
    let api = getApi()

    # Create CPU memory info
    var memInfoHandle: pointer
    let memStatus = api.CreateCpuMemoryInfo(1, 0, addr memInfoHandle)
    checkOrt(memStatus)
    defer:
      if memInfoHandle != nil:
        api.ReleaseMemoryInfo(memInfoHandle)

    # Calculate total elements
    var totalElements: int64 = 1
    for dim in shape:
      totalElements *= dim

    var handle: pointer
    let status = api.CreateTensorWithDataAsOrtValue(
      memInfoHandle,
      data,
      (totalElements * sizeof(float32)).csize_t,
      cast[ptr int64](unsafeAddr shape[0]),
      shape.len.csize_t,
      elemType.cint,
      addr handle
    )
    checkOrt(status)
    result.handle = handle

  proc `=destroy`*(value: var OrtValue) =
    ## Automatic cleanup of OrtValue
    if value.handle != nil:
      let api = getApi()
      api.ReleaseValue(value.handle)
      value.handle = nil

  proc run*(session: OrtSession, inputs: openArray[OrtValue],
            inputNames: openArray[string],
            outputNames: openArray[string]): seq[OrtValue] =
    ## Run inference on the model
    if inputs.len != inputNames.len:
      raise newException(ValueError,
        &"Input count mismatch: {inputs.len} tensors but {inputNames.len} names")

    let api = getApi()

    # Convert input names to cstring array
    var inputNamesCStr = newSeq[cstring](inputNames.len)
    for i, name in inputNames:
      inputNamesCStr[i] = name.cstring

    # Convert output names to cstring array
    var outputNamesCStr = newSeq[cstring](outputNames.len)
    for i, name in outputNames:
      outputNamesCStr[i] = name.cstring

    # Extract input handles
    var inputHandles = newSeq[pointer](inputs.len)
    for i, inp in inputs:
      inputHandles[i] = inp.handle

    # Allocate output handles
    var outputHandles = newSeq[pointer](outputNames.len)

    # Run inference
    let status = api.Run(
      session.handle,
      nil,  # runOptions
      cast[ptr cstring](addr inputNamesCStr[0]),
      cast[ptr pointer](addr inputHandles[0]),
      inputs.len.csize_t,
      cast[ptr cstring](addr outputNamesCStr[0]),
      outputNames.len.csize_t,
      cast[ptr pointer](addr outputHandles[0])
    )
    checkOrt(status)

    # Wrap output handles in OrtValue objects
    result = newSeq[OrtValue](outputNames.len)
    for i in 0 ..< outputNames.len:
      result[i] = OrtValue(handle: outputHandles[i])

  proc getTensorData*[T](value: OrtValue): ptr UncheckedArray[T] =
    ## Get pointer to tensor data from OrtValue
    let api = getApi()
    var dataPtr: pointer
    let status = api.GetTensorMutableData(value.handle, addr dataPtr)
    checkOrt(status)
    result = cast[ptr UncheckedArray[T]](dataPtr)
