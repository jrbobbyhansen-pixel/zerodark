// LoggerConvenience.swift — Typed os_log Logger instances.
//
// Replaces ad-hoc `print()` scatter with structured os_log per subsystem.
// Subsystem: "com.zerodark". Category per domain. Console.app + sysdiagnose
// filter by category. Levels: .debug (noisy), .info, .notice (important),
// .error (recoverable), .fault (assertion violated).

import Foundation
import OSLog

public enum ZDLog {
    public static let subsystem = "com.zerodark"

    public static let navigation  = Logger(subsystem: subsystem, category: "navigation")
    public static let mesh        = Logger(subsystem: subsystem, category: "mesh")
    public static let lidar       = Logger(subsystem: subsystem, category: "lidar")
    public static let ai          = Logger(subsystem: subsystem, category: "ai")
    public static let safety      = Logger(subsystem: subsystem, category: "safety")
    public static let crypto      = Logger(subsystem: subsystem, category: "crypto")
    public static let inference   = Logger(subsystem: subsystem, category: "inference")
    public static let telemetry   = Logger(subsystem: subsystem, category: "telemetry")
    public static let medical     = Logger(subsystem: subsystem, category: "medical")
    public static let storage     = Logger(subsystem: subsystem, category: "storage")
    public static let network     = Logger(subsystem: subsystem, category: "network")
    public static let ui          = Logger(subsystem: subsystem, category: "ui")
    public static let lifecycle   = Logger(subsystem: subsystem, category: "lifecycle")
}

// MARK: - Crash reporting scaffold
//
// Crashlytics / Firebase integration needs a real API key configured per
// deployment (Info.plist + GoogleService-Info.plist). We stub the entry
// point here so call sites can record breadcrumbs and non-fatal errors
// without a hard dependency. When Firebase ships (PR-C9 or later), replace
// the `.recordNonFatal` / `.setBreadcrumb` bodies with real Crashlytics
// calls and register in ZeroDarkApp.init.

@MainActor
public final class CrashReporter {
    public static let shared = CrashReporter()
    private init() {}

    /// Record a non-fatal error for post-hoc aggregation. No-op until a
    /// real crash-reporting backend is wired.
    public func recordNonFatal(_ error: Error, category: ErrorCategory) {
        ZDLog.lifecycle.error("non-fatal [\(category.rawValue, privacy: .public)]: \(error.localizedDescription, privacy: .public)")
    }

    /// Leave a user-action breadcrumb to be attached to any subsequent
    /// crash report. No-op until Firebase is wired.
    public func breadcrumb(_ message: String) {
        ZDLog.lifecycle.info("breadcrumb: \(message, privacy: .public)")
    }
}
