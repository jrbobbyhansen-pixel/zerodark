# ADR 0003 — `@MainActor` singletons for services

**Status:** Accepted
**Date:** 2026-03-01

## Context

Services like `MeshService`, `ChannelManager`, `AppLockManager`,
`LocalInferenceEngine`, `DTNBuffer`, `ThreatClassifier`, and dozens of stores
have singleton identity (one per app) and drive SwiftUI views. We need a
concurrency model that:

- Publishes state changes to SwiftUI cheaply,
- Doesn't require callers to think about actor hopping for every read,
- Still lets heavy I/O move off the main thread.

## Decision

**Services that own observable state are `@MainActor final class ServiceName:
ObservableObject` with a `static let shared = ServiceName()` singleton.**
Heavy I/O (file reads/writes, network, crypto, ML inference) is delegated to
a private `actor` inside the service or to a `Task` at call time.

## Consequences

- Call sites from SwiftUI (`.onAppear`, `.task`, button actions) don't need
  `await`s for quick state reads.
- @Published updates fire on the main thread by default — no explicit hops
  to `DispatchQueue.main` or `MainActor.run`.
- Hot I/O paths still need explicit offload. Pattern:
  ```swift
  @MainActor final class FooStore: ObservableObject {
      private let io = FooFileIO()   // private actor
      public func save(_ item: Foo) async throws {
          try await io.write(item)   // actor hop for disk I/O
          refreshCounts()             // back on main
      }
  }
  ```
- Sendable discipline (PR-C3) matters most at these boundaries — payloads
  crossing into the background actor must be `Sendable`.
- Testing uses `@MainActor` XCTestCase (`@MainActor final class FooTests:
  XCTestCase`) so tests can call into singletons without decorating every
  method.

## When to revisit

If MainActor contention becomes observable (SwiftUI frame drops tied to
service calls), split the affected service into a lightweight MainActor
publisher + a dedicated background actor for logic. Do not convert every
service to an actor wholesale — it destroys SwiftUI ergonomics.
