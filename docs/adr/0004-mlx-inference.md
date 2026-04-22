# ADR 0004 — MLX for on-device LLM inference

**Status:** Accepted
**Date:** 2026-03-01

## Context

ZeroDark needs on-device text + vision inference. Alternatives considered:

1. **CoreML** — Apple-native, great tooling.
2. **llama.cpp** via a Swift wrapper — proven, CPU-optimized, limited GPU.
3. **MLX** (mlx-swift + mlx-swift-lm) — Apple's ML array framework, native
   Apple Silicon Metal backend, first-class Swift API.

## Decision

**Primary: MLX via `mlx-swift-lm`.** Phi-3.5-Mini for text, Moondream2 for
vision when it ships. Models download at first use and are cached in
Documents/.

## Why MLX over CoreML

- CoreML requires model conversion and loses quantization nuances. MLX loads
  HuggingFace quantized weights directly.
- MLX gives Python-identical tensor semantics in Swift, which makes model
  ports / debugging straightforward.
- Streaming token generation is first-class; CoreML is awkward for autoregressive
  decoding.

## Why MLX over llama.cpp

- Native Metal on Apple Silicon outperforms llama.cpp GPU in our benchmarks on
  iPhone 15+ and M-series iPads.
- Swift API avoids the C interop + threadsafety tax llama.cpp brings.
- `mlx-swift-lm` handles the prompt template + tokenization per-model.

## Consequences

- Binary ships with scaffolding; weights download on first run. `LocalInferenceEngine`
  (PR-A3) wraps the download + load with a timeout + inference-duration cap.
- Vendor risk: `mlx-swift-lm` was branch-tracked until PR-C9 pinned it to a
  specific revision. Bumps are intentional and must be accompanied by a
  regression run.
- SHA256 integrity check on model weights is not currently possible — MLX
  downloads from HuggingFace at runtime with no hook to verify against a
  manifest. Documented as a deferred hardening item.
- CPU fallback for devices without recent-enough GPUs is out of scope; we
  target A15 Bionic and later.
