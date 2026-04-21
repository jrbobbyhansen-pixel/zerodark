// PinnedURLSession.swift — Hostname-allowlist-pinned URLSession for ZeroDark.
//
// Strategy: every HTTPS request must target a host on the allowlist. Any other
// host is rejected at the TLS-challenge stage — traffic never leaves the
// device. For hosts on the allowlist we still run iOS's full default TLS
// validation (chain, hostname SAN, revocation), so we get certificate
// rotation and OCSP for free.
//
// This is hostname pinning, not SPKI (public-key) pinning. SPKI pinning
// gives stronger MITM resistance against compromised CAs but requires
// bundling cert fingerprints + a rotation story. For a tactical app that
// mostly talks to a small known set of hosts (elevation tiles, weather,
// optional TAK server) hostname pinning is the more pragmatic default;
// add SPKI pins per-host below when a higher threat model applies.
//
// Usage: replace `URLSession.shared` with `PinnedURLSession.shared.session`.

import Foundation
import CryptoKit

// MARK: - Pin config

public struct HostPin {
    public let host: String
    /// Optional base64-encoded SHA-256 of the SPKI. If present, the cert chain
    /// is additionally checked for a leaf whose SPKI hash matches any of these.
    public let spkiSha256Base64: [String]

    public init(host: String, spkiSha256Base64: [String] = []) {
        self.host = host.lowercased()
        self.spkiSha256Base64 = spkiSha256Base64
    }
}

// MARK: - Allowlist

/// Allowlisted hosts. Every URLSession request through PinnedURLSession
/// must match one. Hosts not here are rejected at TLS time.
public enum PinnedHosts {
    public static var allowlist: [HostPin] = [
        // SRTM elevation tiles (used by TerrainEngine)
        .init(host: "elevation-tiles-prod.s3.amazonaws.com"),
        .init(host: "s3.amazonaws.com"),
        // Local MLX embedding server (dev / loopback)
        .init(host: "127.0.0.1"),
        .init(host: "localhost"),
        // Weather / traffic / model download providers — extend as needed.
        // Add new hosts here instead of bypassing the pinned session.
    ]

    /// Whether `host` is on the allowlist. Case-insensitive.
    public static func isAllowed(_ host: String) -> Bool {
        let h = host.lowercased()
        return allowlist.contains(where: { $0.host == h })
    }

    /// Returns SPKI pins configured for a host (empty = no extra pinning).
    public static func spkiPins(for host: String) -> [String] {
        allowlist.first(where: { $0.host == host.lowercased() })?.spkiSha256Base64 ?? []
    }

    /// Add a host at runtime (e.g. a user-configured TAK server endpoint).
    public static func allow(_ pin: HostPin) {
        guard !allowlist.contains(where: { $0.host == pin.host }) else { return }
        allowlist.append(pin)
    }
}

// MARK: - URLSession wrapper

public final class PinnedURLSession: NSObject {
    public static let shared = PinnedURLSession()

    public let session: URLSession

    private override init() {
        let config = URLSessionConfiguration.default
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.waitsForConnectivity = true
        // Local URLSession — do NOT share with URLSession.shared. Tests and
        // dev code can still use URLSession.shared if they want unpinned access.
        self.session = URLSession(configuration: config,
                                  delegate: PinnedURLSessionDelegate(),
                                  delegateQueue: nil)
        super.init()
    }
}

// MARK: - Delegate

final class PinnedURLSessionDelegate: NSObject, URLSessionDelegate {

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host

        // Step 1 — allowlist check.
        guard PinnedHosts.isAllowed(host) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Step 2 — default TLS evaluation (chain, hostname, expiry).
        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Step 3 — optional SPKI pin check.
        let expectedPins = PinnedHosts.spkiPins(for: host)
        if expectedPins.isEmpty {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }
        if let certPinMatches = verifySPKIPin(trust: serverTrust, pins: expectedPins),
           certPinMatches {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    /// SHA-256 the SPKI of each cert in the chain, compare base64 against `pins`.
    /// Returns nil if the cert data can't be extracted (treat as pin mismatch).
    private func verifySPKIPin(trust: SecTrust, pins: [String]) -> Bool? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              !chain.isEmpty else { return nil }

        for cert in chain {
            // Extract SPKI — Security framework doesn't surface it directly so
            // we hash the full DER cert as a practical substitute. This is the
            // "leaf cert SHA-256" form of pinning (weaker than SPKI but simpler
            // and widely used in practice). Rotating a cert requires updating
            // the pin list; full SPKI hashing can be implemented later via
            // ASN.1 parsing if stricter rotation independence is needed.
            let certData = SecCertificateCopyData(cert) as Data
            let hash = sha256Base64(certData)
            if pins.contains(hash) { return true }
        }
        return false
    }

    private func sha256Base64(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return Data(digest).base64EncodedString()
    }
}
