# Pitfalls Research

**Domain:** Video Engagement Analysis with ML Integration
**Researched:** 2026-02-01
**Confidence:** MEDIUM-HIGH

## Critical Pitfalls

### Pitfall 1: Face Alignment and Low-Quality Input Processing

**What goes wrong:**
Face detection accuracy degrades severely with poor image quality, blur, pose variation, and reduced resolution. The most common failure mode is not the detection algorithm itself, but low-resolution crops, overly compressed frames, and poor face alignment (wrong bounding boxes, inconsistent landmarking).

**Why it happens:**
Developers optimize for processing speed by aggressively downscaling video frames or using high compression rates without validating the impact on ML model accuracy. Video compression artifacts and low-resolution extraction seem acceptable visually but destroy ML model performance.

**How to avoid:**
- Establish minimum resolution thresholds for face detection (typically 80x80 pixels minimum per face)
- Test face detection accuracy across different video compression levels before choosing default encoding settings
- Implement quality checks on extracted frames before passing to ML models
- Use landmark-based alignment verification before accepting detection results
- Document the quality-performance tradeoff in user-facing documentation

**Warning signs:**
- Face detection works well on test videos but fails on user-provided content
- Inconsistent detection rates across different video sources
- High false positive rates on compressed videos
- Detection accuracy varies significantly with video bitrate

**Phase to address:**
Phase 1 (Foundation) - Establish quality gates before ML processing begins

**Sources:**
- [Top 5 Facial Recognition Challenges & Solutions in 2026](https://research.aimultiple.com/facial-recognition-challenges/)
- [Face Recognition Pipeline Clearly Explained](https://medium.com/backprop-labs/face-recognition-pipeline-clearly-explained-f57fc0082750)

---

### Pitfall 2: Memory Management at FFI Boundaries (Nim/C ML Libraries)

**What goes wrong:**
Memory leaks, crashes, or undefined behavior occur at the boundary between Nim's garbage-collected memory and C/C++ ML libraries (OpenCV, ONNX Runtime) that use manual memory management. ref types passed to C libraries get garbage collected while still in use, causing segfaults.

**Why it happens:**
Nim's garbage collector runs unpredictably (usually during memory allocation), and developers assume garbage collection won't happen while C code is executing. String and seq types are allocated from a thread-local heap, but C libraries expect stable memory addresses across thread boundaries.

**How to avoid:**
- Use `GC_ref` to extend lifetime of garbage-collected types before passing to C
- Call `GC_unref` after C code finishes with the reference
- Use manual allocation (`create`, `alloc`, `dealloc`) for single-threaded FFI scenarios
- Use shared allocation (`createShared`, `allocShared`, `deallocShared`) for cross-thread usage
- Wrap all FFI calls in RAII-style Nim objects that manage C resource lifetimes
- Never assume ref type addresses remain stable without explicit GC pinning

**Warning signs:**
- Intermittent crashes that don't reproduce consistently
- Segfaults that only happen under high memory pressure
- Different behavior in debug vs release builds
- Crashes that occur after processing multiple videos but not the first

**Phase to address:**
Phase 1 (Foundation) - Establish FFI memory management patterns before integrating multiple ML libraries

**Sources:**
- [The Nim memory model](https://zevv.nl/nim-memory/)
- [Interop with other languages - The Status Nim style guide](https://status-im.github.io/nim-style-guide/interop.html)
- [Wrapping C libraries in Nim](https://peterme.net/wrapping-c-libraries-in-nim.html)

---

### Pitfall 3: Binary Size Explosion from Static Linking ML Libraries

**What goes wrong:**
Adding ML inference libraries (ONNX Runtime, OpenCV) via static linking causes binary size to balloon from ~10MB to 100MB+ per platform, making cross-compilation and distribution prohibitively expensive. A simple C++ program with static linking grows from 22KB to 8.7MB (400x increase).

**Why it happens:**
ML libraries bundle massive symbol tables, multiple backend implementations (CPU, GPU, various instruction sets), and embedded model formats. Static linking includes unused code paths. For mlpack, boost::serialization alone adds 600KB, and the total binary reaches 4.7MB even after optimization.

**How to avoid:**
- Disable unnecessary functional modules during cross-compilation (see ONNX Runtime build options)
- Use dynamic linking for ML libraries on platforms where you control the runtime environment
- For Windows cross-compilation, evaluate if ML features should be dynamically loaded plugins
- Strip debug symbols and use aggressive compiler optimizations (`-Os`, LTO)
- Consider model-specific builds: only include backends needed for specific features
- Document binary size in build artifacts and set up CI warnings when size thresholds are exceeded

**Warning signs:**
- Build artifacts exceed 100MB per platform
- Cross-compilation times exceed 30 minutes
- Users report long download times
- Binary size doubles with each new ML feature added

**Phase to address:**
Phase 1 (Foundation) - Establish build architecture and linking strategy before adding multiple ML libraries

**Sources:**
- [Binary size: should we use static or dynamic linking?](https://www.sandordargo.com/blog/2024/09/25/dynamic-vs-static-linking-binary-size)
- [What do you think of boost dependencies in mlpack?](https://github.com/mlpack/mlpack/issues/2440)
- [A Practical Guide to C++ Model Inference Based on ONNX Runtime](https://www.oreateai.com/blog/a-practical-guide-to-c-model-inference-based-on-onnx-runtime/7cb1f93bd02e133681d71eb7ee223185)

---

### Pitfall 4: False Positive Rate in Production Video Analysis

**What goes wrong:**
Face detection systems produce 85% false positive rates in real-world deployments (Metropolitan Police finding), causing useless engagement scores, wasted compute on non-faces, and user distrust. False positives are higher in women than men, and higher in elderly/young compared to middle-aged adults, with disproportionate impact on Asian and African American faces.

**Why it happens:**
Models trained on high-quality datasets fail on real-world video with motion blur, partial occlusions, varying lighting, and extreme poses. Default detection thresholds optimized for precision (low false negatives) sacrifice specificity (high false positives). Scene changes in video cause temporal false positives when sliding window approaches don't account for context.

**How to avoid:**
- Implement Scene Change Indicator (SCI) to reduce false positives in temporal sliding windows
- Calibrate detection thresholds on representative user video, not benchmark datasets
- Use multi-frame consensus: require face detection across N consecutive frames before accepting
- Implement demographic fairness testing across race, gender, and age groups
- Add quality scoring to detections: reject low-confidence matches even if they pass threshold
- Log false positive rate as a key metric and expose it to users

**Warning signs:**
- User reports of faces detected in backgrounds, objects, or patterns
- Engagement scores calculated for videos with no people
- Detection rates vary wildly across different user demographics
- Performance degrades when switching from test videos to production data

**Phase to address:**
Phase 2 (Face Detection) - Test and calibrate before releasing engagement features that depend on accurate face detection

**Sources:**
- [The Challenges of AI-Based Face Recognition](https://regulaforensics.com/blog/challenges-of-ai-based-face-recognition/)
- [Reducing false positive rate with Scene Change Indicator](https://pmc.ncbi.nlm.nih.gov/articles/PMC10182539/)
- [Accuracy and Fairness of Facial Recognition in Police Images](https://arxiv.org/html/2505.14320v1)

---

### Pitfall 5: Engagement Scoring Metric Misalignment

**What goes wrong:**
Engagement algorithms prioritize vanity metrics (view count, total watch time) over actual engagement quality, leading to misleading scores. Duration-based prediction models overestimate engagement for long videos and underestimate for short videos due to bimodal distribution. A 20-minute video with 50% retention shows strong engagement, but naive algorithms mark it as poor performance.

**Why it happens:**
Developers port platform-specific algorithms (YouTube, TikTok) without understanding domain differences. TikTok requires 75% completion for algorithmic boost, but that threshold doesn't translate to educational or documentary content. Teams measure what's easy to measure (duration) rather than what matters (satisfaction, attention quality).

**How to avoid:**
- Define engagement metrics specific to auto-editor's use case (likely tutorial/screencast/presentation videos)
- Use completion rate relative to video length category, not absolute percentages
- Weight multi-sentence comments higher than passive metrics (if social features exist)
- Implement segmented analysis: beginning/middle/end retention curves, not just total duration
- Test engagement scores against human judgment on diverse video types
- Document what "engagement" means in your domain and validate it matches user expectations

**Warning signs:**
- High-quality educational videos score lower than short entertainment clips
- Engagement scores don't correlate with user reports of "good" videos
- Algorithm performs well on benchmarks but poorly on user content
- Scores fluctuate wildly with small changes in video length

**Phase to address:**
Phase 3 (Engagement Scoring) - Define domain-specific metrics before implementing algorithms

**Sources:**
- [Beyond Views: Measuring and Predicting Engagement in Online Videos](https://arxiv.org/pdf/1709.02541)
- [Delving Deep into Engagement Prediction of Short Videos](https://arxiv.org/html/2410.00289v1)
- [LinkedIn Algorithm 2026: Text vs Video Strategy](https://growleads.io/blog/linkedin-algorithm-2026-text-vs-video-reach/)

---

### Pitfall 6: Cold Start Problem for New Content

**What goes wrong:**
Engagement prediction fails catastrophically for new creators or videos with limited history. The cold start problem arises from sampling bias in initial interactions, resulting in noisy and inaccurate predictions. Channels with only 1-2 videos in training data are systematically disadvantaged, creating negative feedback loops.

**Why it happens:**
ML models trained on established channels with rich interaction history cannot generalize to sparse data. New creators lack the historical patterns (viewer retention curves, engagement rates, audience demographics) that models rely on.

**How to avoid:**
- Implement content-based features that don't require historical data (scene complexity, audio quality, face prominence)
- Use hybrid approach: content features for new videos, historical patterns for established creators
- Set minimum confidence thresholds: don't report engagement scores until sufficient data exists
- Provide "bootstrapping mode" that uses generic baselines for first N videos
- Document cold start limitations clearly to users
- Consider transfer learning from similar content categories

**Warning signs:**
- Engagement scores for first video differ dramatically from second video of same quality
- New user videos show extreme variance in predicted engagement
- Model confidence metrics reveal high uncertainty but scores are reported anyway
- Users report that engagement analysis is "useless" until they've created many videos

**Phase to address:**
Phase 3 (Engagement Scoring) - Design algorithm to handle sparse data from the start

**Sources:**
- [Delving Deep into Engagement Prediction of Short Videos](https://arxiv.org/html/2410.00289v1)
- [Beyond Views: Measuring and Predicting Engagement](https://www.researchgate.net/publication/319622196_Beyond_Views_Measuring_and_Predicting_Engagement_in_Online_Videos)

---

### Pitfall 7: Frame Extraction Rate vs. Detection Accuracy Tradeoff

**What goes wrong:**
Processing every frame wastes compute (30fps = 1800 frames/minute) but skipping too many frames misses important events. Developers either burn CPU on redundant processing or miss critical face detection opportunities during scene changes. Real-time analysis requires ≥24fps, creating impossible performance requirements for offline batch processing.

**Why it happens:**
No clear guidance exists on optimal frame sampling rates for face detection in pre-recorded video (vs real-time streams). Teams either process every frame to "be safe" or randomly sample frames without understanding detection accuracy impact.

**How to avoid:**
- Implement adaptive frame selection: key frame extraction based on scene changes and motion detection
- Use K-best frame selection: analyze multiple frames, keep highest quality detections
- For offline processing, target 1-5fps analysis rate, not real-time 24fps
- Detect scene changes first, then densely sample around transitions, sparsely sample static scenes
- Validate that selected frames maintain detection accuracy within acceptable threshold (e.g., <5% degradation vs all-frame processing)
- Profile CPU usage and establish frame rate limits that prevent thermal throttling

**Warning signs:**
- CPU utilization at 100% for entire video processing duration
- Processing time scales linearly with video length regardless of content complexity
- Battery drain complaints on laptop usage
- Detection results identical for frames N and N+1 (indicating over-sampling)
- Missing important events that occur between sampled frames

**Phase to address:**
Phase 2 (Face Detection) - Optimize frame extraction before scaling to engagement analysis

**Sources:**
- [Efficient video face recognition based on frame selection](https://pmc.ncbi.nlm.nih.gov/articles/PMC7959602/)
- [CNN based key frame extraction for face in video recognition](https://par.nsf.gov/servlets/purl/10087814)
- [Facial Expression Recognition with Adaptive Frame Rate](https://proceedings.mlr.press/v202/savchenko23a/savchenko23a.pdf)

---

### Pitfall 8: GPU Acceleration Without Proper CPU Fallback

**What goes wrong:**
Features that require GPU acceleration fail completely on systems without compatible GPUs, or worse, silently fall back to broken CPU implementations that produce incorrect results. Users get cryptic OpenCL errors or the tool crashes instead of gracefully degrading.

**Why it happens:**
Developers test only on GPU-equipped machines and assume CPU fallback "just works." Libraries like cuml.accel have limitations causing fallback to scikit-learn CPU implementations, but these fallbacks may have different APIs or produce different results. The "graceful degradation" pattern masks underlying configuration problems.

**How to avoid:**
- Make GPU acceleration explicitly opt-in, not automatic with fallback
- Test CPU-only execution on every platform, not just GPU paths
- Document GPU requirements clearly and check for GPU availability at startup
- Fail fast with clear error messages if GPU is required but unavailable
- If implementing fallback, validate that CPU results match GPU results within tolerance
- Consider CPU-first implementation: optimize CPU path, add GPU as optional speedup
- For whisper.cpp model: document that CUDA is Linux-only (matches CLAUDE.md constraints)

**Warning signs:**
- Users report "it works on my machine" but fails on others
- Performance varies 10x+ between deployments without clear explanation
- Error messages mention CUDA/OpenCL but user doesn't understand
- Fallback silently produces different results than GPU path
- CPU fallback performance is so slow it's unusable (minutes vs seconds)

**Phase to address:**
Phase 1 (Foundation) - Establish GPU/CPU strategy before building features that depend on it

**Sources:**
- [GPU Progressive keeps falling back to CPU due to OpenCL Error](https://discussions.unity.com/t/gpu-progressive-keeps-falling-back-to-cpu-due-to-opencl-error/815457)
- [Graceful JavaScript fallback when GPU not available](https://news.ycombinator.com/item?id=24027673)
- [Resolve SVM Limitations in cuml.accel](https://github.com/rapidsai/cuml/issues/6872)

---

### Pitfall 9: Cross-Platform ONNX/OpenCV Build System Complexity

**What goes wrong:**
ONNX Runtime and OpenCV have conflicting build requirements across Windows/Linux/macOS. Windows requires Visual Studio 2022+ (earlier versions not supported), minimum Windows 10. Linux needs specific GCC versions (8.x and below not supported). macOS cross-compilation from Linux for Windows requires mingw-w64 but ONNX Runtime has limited MinGW support. Protobuf version conflicts between FFmpeg, ONNX Runtime, and OpenCV cause cryptic build failures.

**Why it happens:**
Each ML library evolved independently with different build system assumptions. ONNX Runtime's cross-compilation to ARM is poorly documented (32-bit requires cross-compilation due to memory constraints). OpenCV's CMake configuration with ONNX support fails to recognize ONNX even when properly configured.

**How to avoid:**
- Document minimum toolchain versions in CLAUDE.md before starting (GCC 9+, MSVC 2022+)
- Uninstall conflicting protobuf versions before building ONNX Runtime
- Test cross-compilation early: Windows cross-compile from Linux is critical for auto-editor workflow
- Consider ONNX Runtime pre-built binaries instead of building from source for Windows
- Use OpenCV-lite (opencv_lite project) which bundles compatible ONNX Runtime versions (v1.14-v1.22)
- Set up Docker/container builds to ensure reproducible toolchain environments
- Add CMake feature flags to disable ML features if build dependencies are unavailable

**Warning signs:**
- Builds succeed on one platform but fail on another
- CMake finds libraries but linker fails
- Protobuf version errors during build
- Cross-compilation takes 3+ hours (indicates redundant builds or missing cached artifacts)
- Different developers get different build results from same source

**Phase to address:**
Phase 1 (Foundation) - Validate cross-platform builds before adding ML dependencies

**Sources:**
- [Build for inferencing - ONNX Runtime](https://onnxruntime.ai/docs/build/inferencing.html)
- [How to enable ONNX Runtime Windows GPU version into OpenCV CMake flag?](https://github.com/opencv/opencv/issues/26689)
- [Cross compilation of onnxruntime for ARMv7](https://github.com/microsoft/onnxruntime/issues/21439)
- [opencv_lite: OpenCV API with ONNX by ONNXRuntime](https://github.com/zihaomu/opencv_lite)

---

### Pitfall 10: Model Quantization Accuracy Degradation

**What goes wrong:**
Quantizing face detection or engagement models from FP32 to INT8/INT4 to reduce binary size and inference time causes accuracy degradation. Poorly calibrated quantization leads to 25%+ accuracy loss. Users get faster but unreliable results, undermining trust in the tool.

**Why it happens:**
Developers quantize models without validation on representative data. Default quantization settings optimize for model size/speed without testing accuracy impact. Poor calibration data selection (using test set instead of diverse real-world samples) is the most common cause of degradation.

**How to avoid:**
- Establish accuracy baselines with FP32 models before quantizing
- Use quantization-aware training (QAT) if training models yourself, not just post-training quantization
- Test quantized models on diverse video samples: different resolutions, compression levels, demographics
- Document acceptable accuracy degradation thresholds (e.g., <3% for INT8, <5% for INT4)
- Use SmoothQuant, FlatQuant, or ZeroQAT techniques for INT4 if needed
- Provide option to download full-precision models for users who prioritize accuracy over speed
- Include quantization validation in CI: fail builds if accuracy drops below threshold

**Warning signs:**
- Face detection accuracy drops from 95% to 70% after quantization
- Engagement scores show high variance on similar content after model update
- Users report model worked better in previous version
- Quantized model performs well on test set but poorly on production data
- Model size decreased 4x but accuracy decreased 20%+

**Phase to address:**
Phase 2 (Face Detection) - Validate quantization before deploying models to users

**Sources:**
- [Model Quantization: Concepts, Methods, and Why It Matters](https://developer.nvidia.com/blog/model-quantization-concepts-methods-and-why-it-matters/)
- [We ran over half a million evaluations on quantized LLMs](https://developers.redhat.com/articles/2024/10/17/we-ran-over-half-million-evaluations-quantized-llms)
- [LLM Quantization: BF16 vs FP8 vs INT4 in 2026](https://research.aimultiple.com/llm-quantization/)

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Processing every video frame | Guaranteed not to miss events | 10-30x CPU waste, thermal throttling | Never - use adaptive frame selection |
| Using cloud face detection APIs for prototyping | Fast initial implementation | Violates "no cloud" constraint, vendor lock-in | Only for proof-of-concept demos, never production |
| Hard-coding detection thresholds from papers | Quick to implement | High false positive rates on real data | Only as initial values - must calibrate on user data |
| Static linking all ML libraries | Simpler deployment | 100MB+ binaries, slow cross-compilation | Small single-platform tools, not cross-platform CLI |
| Skipping demographic fairness testing | Faster development | Biased detection, potential PR disasters | Never for user-facing features |
| Single-threaded video processing | Simple to debug | Can't utilize multi-core CPUs | Initial implementation - must parallelize for v1.0 |
| Copying whisper.cpp integration pattern for all ML | Reuse existing code patterns | Memory management issues - whisper.cpp is audio, faces are video frames | Never - each library needs custom FFI wrapper |
| Using LTO (Link-Time Optimization) for all builds | Smaller binaries | 5-10x slower compilation, harder debugging | Only for release builds, never development |

## Integration Gotchas

Common mistakes when connecting to external ML libraries.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| ONNX Runtime | Assuming CPU fallback works automatically | Explicitly test CPU-only builds, make GPU opt-in |
| OpenCV | Using system OpenCV instead of building from source | Build OpenCV with specific ONNX Runtime version to avoid ABI conflicts |
| whisper.cpp | Assuming CUDA works on all platforms | Document Linux-only CUDA support, provide CPU path for Windows/macOS |
| Face detection models | Loading models from disk on every frame | Load once at startup, cache in memory, reuse across frames |
| FFmpeg frame extraction | Converting every frame to RGB before analysis | Extract YUV, convert only frames that pass initial filters |
| Nim GC with C++ libraries | Passing Nim strings directly to C++ | Copy to C-allocated buffer or use cstring with lifetime management |
| Model file paths | Hard-coding absolute paths to models | Use relative paths from executable or environment variables |
| Thread pools for video processing | Creating new threads per video | Initialize thread pool once, reuse for all videos |

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Processing 4K video at full resolution | Slow processing, high memory usage | Downscale to 1080p or 720p for analysis, preserve original for output | >10 minute 4K videos |
| Synchronous video processing | UI freezes, appears hung | Use background threads, show progress | Any video >1 minute |
| Loading entire video into RAM | Fast seek, slow startup, OOM crashes | Stream frames, process in chunks | Videos >1GB |
| Re-running face detection on cached frames | Wasted CPU on unchanged content | Hash frames, skip detection if hash matches previous run | Re-processing edited videos |
| Global model singleton | Thread contention, serialized processing | Thread-local model instances or model pool | Batch processing multiple videos |
| Unbounded output buffer | Memory grows linearly with video length | Streaming write to disk, fixed-size ring buffer | Videos >30 minutes |
| Linear search through detected faces | O(n²) complexity for matching across frames | Spatial hash table or KD-tree for face positions | >100 faces per video |
| Storing full-resolution face crops | Gigabytes of cached data | Store embeddings/features only, regenerate crops if needed | Videos with many faces |

## Security Mistakes

Domain-specific security issues beyond general software security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Loading untrusted ONNX models | Arbitrary code execution via malicious model files | Validate model signatures, sandbox model loading, use only trusted model sources |
| Processing user videos without sanitization | FFmpeg codec vulnerabilities, malicious video files | Run FFmpeg in sandbox, validate container format before processing, set resource limits |
| Exposing model file paths in error messages | Information disclosure about system layout | Use generic error messages, log details only to secure log files |
| Caching face embeddings without encryption | Privacy violation if cache stolen | Encrypt cached embeddings at rest, clear cache on exit option |
| Writing temporary frames to /tmp | Sensitive video frames readable by other users | Use user-specific temp directory with restricted permissions |
| Logging detected face coordinates | Privacy violation in logs | Truncate or hash identifying information in logs |
| Downloading models over HTTP | Man-in-the-middle attacks, poisoned models | Use HTTPS only, verify checksums/signatures |
| Running FFmpeg with shell=True | Command injection via malicious filenames | Use subprocess with array arguments, never shell interpolation |

## UX Pitfalls

Common user experience mistakes in this domain.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| No progress indication during processing | Users think tool is frozen, kill process | Show frame-by-frame progress, estimated time remaining |
| Cryptic ML error messages | Users don't know if problem is video or tool | Detect common issues (no faces found, low quality) and provide actionable messages |
| Requiring GPU without clear documentation | Tool fails with obscure errors | Detect GPU at startup, show clear message if required but missing |
| Silent accuracy degradation | Users don't know when to trust results | Show confidence scores, warn when quality thresholds not met |
| Processing videos in current directory | Clutters user workspace with temp files | Use dedicated cache directory, clean up automatically |
| Binary 100MB+ downloads | Users abandon during download | Offer minimal builds, download models on-demand |
| Engagement scores without context | Numbers are meaningless without baseline | Show percentile ranking, comparison to similar videos |
| No way to verify face detection results | Users can't debug wrong results | Offer optional debug output with annotated frames |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Face Detection:** Often missing demographic fairness validation - verify accuracy across race/gender/age groups, not just benchmark datasets
- [ ] **Model Integration:** Often missing memory leak testing - run for 1000+ videos and monitor RSS growth
- [ ] **Cross-compilation:** Often missing actual runtime testing on target platform - verify .exe works on Windows, not just that build succeeds
- [ ] **Engagement Scoring:** Often missing cold start handling - verify behavior on videos from new creators with no history
- [ ] **FFI Wrappers:** Often missing error propagation from C to Nim - verify Nim exceptions capture C errors, not just success paths
- [ ] **Frame Extraction:** Often missing scene change detection - verify key events detected, not just uniform sampling
- [ ] **GPU Acceleration:** Often missing CPU-only testing - verify works on systems without compatible GPU
- [ ] **Model Quantization:** Often missing accuracy validation on production data - verify performance on real user videos, not test sets
- [ ] **Progress Reporting:** Often missing cancellation handling - verify clean shutdown when user interrupts long-running processing
- [ ] **Cache Management:** Often missing size limits - verify cache doesn't grow unbounded on large video libraries

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Binary size explosion | MEDIUM | 1. Profile binary to identify largest symbols. 2. Add CMake flags to disable unused backends. 3. Consider dynamic linking for largest libraries. 4. Use UPX compression for release binaries |
| False positive rate in production | HIGH | 1. Collect production samples with ground truth. 2. Retrain or recalibrate models. 3. Implement multi-frame consensus. 4. Add user feedback mechanism to improve over time |
| Memory leaks at FFI boundary | HIGH | 1. Use Valgrind/ASan to identify leak location. 2. Audit all GC_ref/GC_unref pairs. 3. Convert to RAII pattern. 4. Add memory regression tests to CI |
| Cross-platform build failures | MEDIUM | 1. Set up CI for all target platforms. 2. Use Docker containers for reproducible builds. 3. Document exact toolchain versions. 4. Consider pre-built binaries for problematic libraries |
| Engagement metric misalignment | LOW | 1. Gather user feedback on score quality. 2. A/B test alternative metrics. 3. Adjust weights based on correlation with user satisfaction. 4. Document metric definition changes in changelog |
| Frame extraction too slow | LOW | 1. Profile to find bottleneck. 2. Implement adaptive sampling. 3. Add parallel frame decoding. 4. Use hardware-accelerated decoding if available |
| Model quantization accuracy loss | MEDIUM | 1. Roll back to full-precision model. 2. Use QAT if possible. 3. Try alternative quantization techniques (SmoothQuant). 4. Offer both quantized and full models |
| Cold start prediction failure | LOW | 1. Implement content-based fallback. 2. Set minimum confidence thresholds. 3. Show "insufficient data" message instead of bad predictions. 4. Document expected accuracy with N videos |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Memory management at FFI boundaries | Phase 1: Foundation | Run 1000 videos through pipeline without RSS growth >10% |
| Binary size explosion | Phase 1: Foundation | CI fails if binary exceeds 50MB per platform |
| Cross-platform build complexity | Phase 1: Foundation | All platforms build and pass smoke tests in CI |
| GPU acceleration without CPU fallback | Phase 1: Foundation | Unit tests pass on CPU-only CI runner |
| Frame extraction rate vs accuracy | Phase 2: Face Detection | Accuracy within 5% of all-frame processing at 10% frame rate |
| Face alignment and low quality input | Phase 2: Face Detection | Detection accuracy >90% on compressed user videos (not benchmarks) |
| False positive rate in production | Phase 2: Face Detection | FPR <15% on diverse test set (Metropolitan Police was 85%) |
| Model quantization accuracy degradation | Phase 2: Face Detection | Quantized model accuracy within 3% of FP32 baseline |
| Engagement metric misalignment | Phase 3: Engagement Scoring | User survey shows >80% agreement with "good video" labels |
| Cold start prediction problem | Phase 3: Engagement Scoring | Confidence scores <50% flagged for videos with <5 historical samples |
| Speaker tracking false positives | Phase 4: Speaker Reframing | Multi-frame consensus reduces false positives by >50% vs single-frame |

## Sources

### Face Detection and Video Analysis
- [Top 5 Facial Recognition Challenges & Solutions in 2026](https://research.aimultiple.com/facial-recognition-challenges/)
- [Face Recognition Pipeline Clearly Explained](https://medium.com/backprop-labs/face-recognition-pipeline-clearly-explained-f57fc0082750)
- [Efficient video face recognition based on frame selection](https://pmc.ncbi.nlm.nih.gov/articles/PMC7959602/)
- [Reducing false positive rate with Scene Change Indicator](https://pmc.ncbi.nlm.nih.gov/articles/PMC10182539/)
- [Accuracy and Fairness of Facial Recognition in Police Images](https://arxiv.org/html/2505.14320v1)
- [The Challenges of AI-Based Face Recognition](https://regulaforensics.com/blog/challenges-of-ai-based-face-recognition/)

### Video Engagement and Scoring
- [Beyond Views: Measuring and Predicting Engagement in Online Videos](https://arxiv.org/pdf/1709.02541)
- [Delving Deep into Engagement Prediction of Short Videos](https://arxiv.org/html/2410.00289v1)
- [LinkedIn Algorithm 2026: Text vs Video Strategy](https://growleads.io/blog/linkedin-algorithm-2026-text-vs-video-reach/)

### ML Integration and Deployment
- [Model Quantization: Concepts, Methods, and Why It Matters](https://developer.nvidia.com/blog/model-quantization-concepts-methods-and-why-it-matters/)
- [We ran over half a million evaluations on quantized LLMs](https://developers.redhat.com/articles/2024/10/17/we-ran-over-half-million-evaluations-quantized-llms)
- [LLM Quantization: BF16 vs FP8 vs INT4 in 2026](https://research.aimultiple.com/llm-quantization/)
- [ML Inference Runtimes in 2026: An Architect's Guide](https://medium.com/@digvijay17july/ml-inference-runtimes-in-2026-an-architects-guide-to-choosing-the-right-engine-d3989a87d052)

### Cross-Platform Build Systems
- [Build for inferencing - ONNX Runtime](https://onnxruntime.ai/docs/build/inferencing.html)
- [How to enable ONNX Runtime Windows GPU version into OpenCV CMake flag?](https://github.com/opencv/opencv/issues/26689)
- [Cross compilation of onnxruntime for ARMv7](https://github.com/microsoft/onnxruntime/issues/21439)
- [opencv_lite: OpenCV API with ONNX by ONNXRuntime](https://github.com/zihaomu/opencv_lite)
- [Binary size: should we use static or dynamic linking?](https://www.sandordargo.com/blog/2024/09/25/dynamic-vs-static-linking-binary-size)

### Nim FFI and Memory Management
- [The Nim memory model](https://zevv.nl/nim-memory/)
- [Interop with other languages - The Status Nim style guide](https://status-im.github.io/nim-style-guide/interop.html)
- [Wrapping C libraries in Nim](https://peterme.net/wrapping-c-libraries-in-nim.html)

### Speaker Tracking and Automation
- [AI Speaker Focus: Auto Framing for Video](https://www.kapwing.com/ai/auto-speaker-focus)
- [Reducing false positive rate in real-time face recognition](https://pmc.ncbi.nlm.nih.gov/articles/PMC10182539/)

### GPU Acceleration and Fallback
- [GPU Progressive keeps falling back to CPU due to OpenCL Error](https://discussions.unity.com/t/gpu-progressive-keeps-falling-back-to-cpu-due-to-opencl-error/815457)
- [Graceful JavaScript fallback when GPU not available](https://news.ycombinator.com/item?id=24027673)
- [Resolve SVM Limitations in cuml.accel](https://github.com/rapidsai/cuml/issues/6872)

---
*Pitfalls research for: Video Engagement Analysis with ML Integration*
*Researched: 2026-02-01*
