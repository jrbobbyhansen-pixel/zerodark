# ADR 0007 — Hybrid BM25 + embedding RAG for intel lookup

**Status:** Accepted
**Date:** 2026-03-01

## Context

The Intel tab answers natural-language queries against the corpus in
`FastLibraryView` + `KnowledgeRAG`. Options for retrieval:

1. **Embedding-only** — semantic similarity via an on-device embedding model.
2. **BM25 keyword** — classic sparse retrieval.
3. **Hybrid** — combine both with reciprocal rank fusion or weighted scores.

## Decision

**Hybrid: BM25 top-K + embedding rerank**, surfaced through `IntelCorpus` and
`VerifyPipeline`.

## Why

- Pure embedding retrieval is wrong in tactical domains — acronyms (MGRS,
  EEI, PIR) and call signs don't embed meaningfully. BM25 catches them.
- Pure BM25 misses paraphrases ("exfil route" vs "egress corridor"). Embeddings
  catch those.
- Reciprocal-rank fusion turns out to be robust across our test queries;
  weighted sum needed per-query tuning.
- `VerifyPipeline` adds citation-grounding on top so the operator can see
  which chunks backed the answer — this matters more than recall in ops
  contexts.

## Consequences

- The embedding model ships in the binary (smaller than the LLM — a few
  dozen MB). `IntelCorpus` caches the embedding index on disk (PR #21).
- First query after cold-start rebuilds the index if corpus changed — users
  see a spinner with "indexing X documents."
- Updating the corpus means re-embedding those docs; BM25 rebuilds are cheap.
- No server-side retrieval. Everything is on-device per ADR 0001.

## When to revisit

If corpus size exceeds ~50 k chunks, consider a proper vector index (HNSW)
over the array-scan we use today.
