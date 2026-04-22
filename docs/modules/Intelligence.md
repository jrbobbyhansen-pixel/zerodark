# Intelligence

On-device AI: text inference, vision, RAG, threat classification, telemetry.

## Entry points

- **`LocalInferenceEngine.shared`** — MLX-backed Phi-3.5 text LLM. Handles
  model download + load + timeout-bounded `generate(...)`. PR-A3 added
  first-token-stall + total-duration caps.
- **`VisionInferenceEngine.shared`** — Moondream2 vision wrapper (model not
  yet bundled; scaffold only).
- **`ThreatClassifier.shared`** — LLM-classified threat reports with per-
  category confidence thresholds + suppress-list (PR-A4).
- **`IntelCorpus.shared`** — BM25 + embedding index for knowledge corpus.
  Caches embeddings on disk (PR #21).
- **`KnowledgeRAG`** — retrieval pipeline used by `VerifyPipeline` for
  citation-grounded answers.
- **`TacticalQueryParser`** — structure-extraction for common intel queries
  ("nearest peer", "last observation of …").

## Error handling

Inference + retrieval paths route failures through `ErrorReporter`
(PR-A5) with category `.inference`. Inference timeouts
(`InferenceTimeoutError.firstTokenStall` or `.totalDurationExceeded`)
surface a `"Inference timed out."` user message so the operator knows
the model did not just produce a short answer.

## Cross-references

- MLX decision: [ADR 0004](../adr/0004-mlx-inference.md).
- Hybrid-RAG decision: [ADR 0007](../adr/0007-hybrid-rag.md).
- ThreatClassifier thresholds + suppress: PR-A4, tests in
  `ThreatClassifierTests.swift`.

## Testing

`ThreatClassifierTests` covers the threshold + suppress-list pure logic (the
LLM call itself is not exercised in unit tests — see test file preamble).
