// IntegrationHealthMonitor.swift — Periodic reachability checks for the
// external services ZeroDark depends on (SRTM terrain tiles, weather,
// TAK server). Replaces ad-hoc silent failures where a dead endpoint
// would simply return stale data with no operator feedback.
//
// Each registered service provides a URL + a "probe" closure. The
// monitor runs probes on a schedule, records the last success/failure
// timestamp, and publishes a snapshot the UI can render. Failures route
// through ErrorReporter so they surface uniformly.

import Foundation
import OSLog

/// Well-known services the monitor tracks. Extend as integrations land.
public enum IntegrationService: String, CaseIterable, Codable, Sendable {
    case srtm    = "srtm"     // NASA SRTM v3 terrain tiles
    case weather = "weather"  // Open-Meteo / NWS / ECMWF
    case tak     = "tak"      // FreeTAK / TAK Server CoT feed

    public var displayName: String {
        switch self {
        case .srtm:    return "SRTM Terrain"
        case .weather: return "Weather"
        case .tak:     return "TAK Server"
        }
    }
}

/// Lifecycle state for one integration. `lastSuccess`/`lastFailure` are
/// both optional — absent until the first probe completes.
public struct IntegrationHealth: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable {
        case unknown        // no probe has completed yet
        case healthy        // last probe succeeded within tolerance
        case degraded       // probing but last response was slow/unexpected
        case unreachable    // last probe failed
    }

    public var service: IntegrationService
    public var status: Status
    public var lastSuccess: Date?
    public var lastFailure: Date?
    public var lastLatencyMillis: Int?
    public var consecutiveFailures: Int

    public init(service: IntegrationService) {
        self.service = service
        self.status = .unknown
        self.lastSuccess = nil
        self.lastFailure = nil
        self.lastLatencyMillis = nil
        self.consecutiveFailures = 0
    }
}

/// A probe is a closure that succeeds with a latency measurement or
/// fails with an error. Implementations are expected to be side-effect-free
/// (HEAD request, small GET, etc.) so probing doesn't cost bandwidth.
public typealias IntegrationProbe = @Sendable () async throws -> Void

@MainActor
public final class IntegrationHealthMonitor: ObservableObject {
    public static let shared = IntegrationHealthMonitor()

    @Published public private(set) var states: [IntegrationService: IntegrationHealth] = [:]

    private var probes: [IntegrationService: IntegrationProbe] = [:]
    private var tickTask: Task<Void, Never>?
    private let log = ZDLog.network
    private let probeTimeout: TimeInterval = 8.0
    /// Minimum interval between successive probes of the same service.
    /// The monitor's tick runs faster than this so new probes can be
    /// registered without waiting a full cycle.
    public var probeInterval: TimeInterval = 60.0
    /// Time between monitor ticks. Low enough that a newly-registered
    /// probe runs within ~5s of registration.
    private var tickInterval: TimeInterval = 5.0

    private init() {
        for service in IntegrationService.allCases {
            states[service] = IntegrationHealth(service: service)
        }
    }

    /// Register a probe for one service. Safe to call multiple times — a
    /// new registration replaces the prior probe.
    public func register(_ service: IntegrationService, probe: @escaping IntegrationProbe) {
        probes[service] = probe
    }

    /// Start the monitor's tick loop. Idempotent.
    public func start() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runOverdueProbes()
                try? await Task.sleep(nanoseconds: UInt64((self?.tickInterval ?? 5) * 1_000_000_000))
            }
        }
    }

    public func stop() {
        tickTask?.cancel()
        tickTask = nil
    }

    /// Force an immediate probe of one service, regardless of schedule.
    /// Useful for "Retry" buttons in UI.
    public func probeNow(_ service: IntegrationService) async {
        await runProbe(for: service)
    }

    public func health(for service: IntegrationService) -> IntegrationHealth {
        states[service] ?? IntegrationHealth(service: service)
    }

    /// Clear registered probes and reset all service states to `.unknown`.
    /// ONLY for tests — the monitor is a shared singleton, so tests that
    /// assert on initial state must reset first.
    func _resetForTesting() {
        probes.removeAll()
        for service in IntegrationService.allCases {
            states[service] = IntegrationHealth(service: service)
        }
        tickTask?.cancel()
        tickTask = nil
    }

    public var overallStatus: IntegrationHealth.Status {
        let statuses = states.values.map(\.status)
        if statuses.contains(.unreachable) { return .unreachable }
        if statuses.contains(.degraded)    { return .degraded }
        if statuses.allSatisfy({ $0 == .healthy }) { return .healthy }
        return .unknown
    }

    // MARK: - Internals

    private func runOverdueProbes() async {
        let now = Date()
        for service in probes.keys {
            let health = states[service] ?? IntegrationHealth(service: service)
            let last = max(health.lastSuccess ?? .distantPast, health.lastFailure ?? .distantPast)
            if now.timeIntervalSince(last) >= probeInterval {
                await runProbe(for: service)
            }
        }
    }

    private func runProbe(for service: IntegrationService) async {
        guard let probe = probes[service] else { return }
        var health = states[service] ?? IntegrationHealth(service: service)
        let start = Date()
        do {
            try await withTimeout(seconds: probeTimeout, operation: "probe:\(service.rawValue)") {
                try await probe()
            }
            let latencyMs = Int(Date().timeIntervalSince(start) * 1000)
            health.lastSuccess = Date()
            health.lastLatencyMillis = latencyMs
            health.consecutiveFailures = 0
            health.status = latencyMs > 3000 ? .degraded : .healthy
            log.debug("probe ok \(service.rawValue, privacy: .public) \(latencyMs)ms")
        } catch {
            health.lastFailure = Date()
            health.consecutiveFailures += 1
            health.status = .unreachable
            log.error("probe fail \(service.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            // Only surface user-facing errors after a couple of failures so
            // one blip doesn't spam the operator.
            let userMessage: String? = health.consecutiveFailures >= 2
                ? "\(service.displayName) is unreachable. Falling back to cached data."
                : nil
            ErrorReporter.shared.report(
                category: .network,
                error: error,
                message: "integration_probe_failed service:\(service.rawValue)",
                userMessage: userMessage
            )
        }
        states[service] = health
    }
}

/// Default probe factories. Callers wire the real URL at integration time
/// so the monitor stays decoupled from any specific endpoint choice.
public enum DefaultIntegrationProbes {
    /// HEAD request. Any 2xx / 3xx counts as success. Other statuses or
    /// transport errors throw.
    public static func head(_ url: URL, session: URLSession = .shared) -> IntegrationProbe {
        { @Sendable in
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 6.0
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
        }
    }

    /// GET, check HTTP status — used where HEAD is not allowed.
    public static func get(_ url: URL, session: URLSession = .shared) -> IntegrationProbe {
        { @Sendable in
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 6.0
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
        }
    }
}
