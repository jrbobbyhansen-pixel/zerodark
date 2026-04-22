// ErrorReporter.swift — Centralized error-surfacing for ZeroDark.
//
// Replaces the pattern of silent `try?` swallowing failures across services.
// Every subsystem calls `ErrorReporter.shared.report(category:error:...)`
// when a recoverable failure occurs; the reporter:
//   1. Publishes the latest error for the UI to surface in a banner/toast.
//   2. Feeds AuditLogger so operators can inspect failure history.
//   3. os_log's the failure for Console.app / sysdiagnose.
//
// This is not a crash-reporting framework (that's Crashlytics / Firebase,
// which PR-A6 handles). This is the layer below that: surface recoverable
// errors to the operator + audit trail, before they escalate.

import Foundation
import Combine
import OSLog

// MARK: - Categories

public enum ErrorCategory: String, Codable, Sendable {
    case navigation
    case mesh
    case crypto
    case inference
    case lidar
    case storage
    case network
    case safety
    case medical
    case hardware
    case other
}

// MARK: - Report

public struct ErrorReport: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let category: ErrorCategory
    public let message: String
    public let underlying: String?
    public let userFacing: String?

    public init(category: ErrorCategory, message: String, underlying: String?, userFacing: String?) {
        self.id = UUID()
        self.timestamp = Date()
        self.category = category
        self.message = message
        self.underlying = underlying
        self.userFacing = userFacing
    }
}

// MARK: - Reporter

@MainActor
public final class ErrorReporter: ObservableObject {
    public static let shared = ErrorReporter()

    /// Most-recent error to display in a toast / banner. Views watch this
    /// and clear it via `dismissLatest()` after showing.
    @Published public private(set) var latest: ErrorReport?

    /// Rolling window of recent reports (last 500). Bounded growth.
    @Published public private(set) var recent: [ErrorReport] = []

    private let maxRecent = 500
    private let log = Logger(subsystem: "com.zerodark", category: "ErrorReporter")

    private init() {}

    /// Report a recoverable failure.
    /// - Parameters:
    ///   - category: subsystem responsible
    ///   - error: the underlying Error (if any)
    ///   - message: developer-facing summary (what went wrong internally)
    ///   - userMessage: optional operator-facing text for a toast/banner.
    ///                  Nil = silent audit-only (use for very noisy paths
    ///                  where banners would be disruptive).
    public func report(
        category: ErrorCategory,
        error: Error? = nil,
        message: String,
        userMessage: String? = nil
    ) {
        let report = ErrorReport(
            category: category,
            message: message,
            underlying: error?.localizedDescription,
            userFacing: userMessage
        )

        // Bounded append.
        recent.insert(report, at: 0)
        if recent.count > maxRecent {
            recent = Array(recent.prefix(maxRecent))
        }

        // Surface to UI only if the caller supplied user-facing text.
        if userMessage != nil { latest = report }

        // os_log for Console.app / sysdiagnose visibility.
        if let err = error {
            log.error("[\(category.rawValue, privacy: .public)] \(message, privacy: .public) — \(err.localizedDescription, privacy: .public)")
        } else {
            log.error("[\(category.rawValue, privacy: .public)] \(message, privacy: .public)")
        }

        // Audit trail (AuditLogger handles persistence + rotation).
        AuditLogger.shared.log(
            .observationLogged,
            detail: "error category:\(category.rawValue) msg:\(message)"
        )
    }

    /// Call after a toast / banner has been shown.
    public func dismissLatest() { latest = nil }

    /// Clear the rolling window. Use from Settings > Clear Error History.
    public func clearRecent() {
        recent.removeAll()
        latest = nil
    }
}
