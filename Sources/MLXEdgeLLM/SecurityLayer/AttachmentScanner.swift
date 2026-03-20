// AttachmentScanner.swift — File Attachment Security Scanner
// MIME type validation, magic bytes checking, and deny-list scanning

import Foundation
import CryptoKit
import SwiftUI

actor AttachmentScanner {
    static let shared = AttachmentScanner()

    private let maxFileSize: Int = 50 * 1024 * 1024  // 50 MB
    private let suspiciousExtensions = Set([
        "exe", "sh", "py", "bat", "ps1", "app", "dmg", "dll",
        "scr", "vbs", "js", "jar", "class", "so", "dylib"
    ])

    private var denyListHashes: Set<String> = [
        // Pre-populated with known-bad file hashes (SHA-256)
        // In production, these would be updated from a trusted source
    ]

    private init() {
        loadDenyList()
    }

    func scan(_ data: Data, filename: String) async -> ScanResult {
        let sha256 = sha256Hash(data)

        // Check file size
        if data.count > maxFileSize {
            return ScanResult(
                approved: false,
                detectedMime: getMimeType(data),
                claimedMime: getClaimedMimeType(filename),
                sha256: sha256,
                flags: [.oversized]
            )
        }

        // Check hash against deny list
        if denyListHashes.contains(sha256) {
            return ScanResult(
                approved: false,
                detectedMime: getMimeType(data),
                claimedMime: getClaimedMimeType(filename),
                sha256: sha256,
                flags: [.knownBad]
            )
        }

        // Check extension and MIME mismatch
        var flags: [ScanFlag] = []

        let detectedMime = getMimeType(data)
        let claimedMime = getClaimedMimeType(filename)

        if detectedMime != claimedMime && !detectedMime.isEmpty && !claimedMime.isEmpty {
            flags.append(.mismatch)
        }

        // Check for suspicious extensions
        let fileExtension = (filename as NSString).pathExtension.lowercased()
        if suspiciousExtensions.contains(fileExtension) {
            flags.append(.suspiciousExtension)
        }

        let approved = flags.isEmpty

        return ScanResult(
            approved: approved,
            detectedMime: detectedMime,
            claimedMime: claimedMime,
            sha256: sha256,
            flags: flags
        )
    }

    func scan(url: URL) async -> ScanResult {
        do {
            let data = try Data(contentsOf: url)
            return await scan(data, filename: url.lastPathComponent)
        } catch {
            return ScanResult(
                approved: false,
                detectedMime: "",
                claimedMime: getClaimedMimeType(url.lastPathComponent),
                sha256: "",
                flags: [.readError]
            )
        }
    }

    // MARK: - MIME Type Detection

    private func getMimeType(_ data: Data) -> String {
        // Check file signatures (magic bytes)
        guard data.count >= 4 else { return "" }

        let prefix = data.prefix(4)
        let bytes = [UInt8](prefix)

        // PNG
        if bytes.count >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return "image/png"
        }

        // JPEG
        if bytes.count >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8 {
            return "image/jpeg"
        }

        // PDF
        if bytes.count >= 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46 {
            return "application/pdf"
        }

        // ZIP (includes docx, xlsx, etc.)
        if bytes.count >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04 {
            return "application/zip"
        }

        // GIF
        if bytes.count >= 3 && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 {
            return "image/gif"
        }

        // ELF (Linux executable)
        if bytes.count >= 4 && bytes[0] == 0x7F && bytes[1] == 0x45 && bytes[2] == 0x4C && bytes[3] == 0x46 {
            return "application/x-elf"
        }

        // Mach-O (macOS executable)
        if bytes.count >= 4 {
            let uint32 = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
            if uint32 == 0xFEEDFACF || uint32 == 0xFEEDFACE {
                return "application/x-macho"
            }
        }

        // UTF-8 text
        if data.count > 0, let _ = String(data: data, encoding: .utf8) {
            if !data.contains(0) {  // No null bytes (binary indicator)
                return "text/plain"
            }
        }

        return ""
    }

    private func getClaimedMimeType(_ filename: String) -> String {
        let fileExtension = (filename as NSString).pathExtension.lowercased()

        let mimeMap: [String: String] = [
            "png": "image/png",
            "jpg": "image/jpeg",
            "jpeg": "image/jpeg",
            "pdf": "application/pdf",
            "zip": "application/zip",
            "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "txt": "text/plain",
            "gif": "image/gif",
            "bmp": "image/bmp",
            "webp": "image/webp",
            "mp4": "video/mp4",
            "mp3": "audio/mpeg",
            "wav": "audio/wav",
            "m4a": "audio/mp4",
            "exe": "application/x-msdownload",
            "app": "application/x-apple-application-bundle",
            "sh": "application/x-shellscript",
            "py": "text/x-python",
            "js": "application/javascript"
        ]

        return mimeMap[fileExtension] ?? ""
    }

    // MARK: - Hashing & Deny List

    private func sha256Hash(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    private func loadDenyList() {
        // In production, load from a trusted, regularly updated source
        // This could be:
        // 1. A local file bundled with the app
        // 2. A remote endpoint (with pinned certificate)
        // 3. A hash of common malware samples from VirusShare metadata

        // For now, use empty set (no known-bad hashes pre-loaded)
        // Users can add hashes manually via: denyListHashes.insert(sha256String)
    }

    func addToDenyList(_ sha256Hash: String) {
        denyListHashes.insert(sha256Hash)
    }

    func removeFromDenyList(_ sha256Hash: String) {
        denyListHashes.remove(sha256Hash)
    }
}

// MARK: - Scan Result Types

struct ScanResult {
    let approved: Bool
    let detectedMime: String
    let claimedMime: String
    let sha256: String
    let flags: [ScanFlag]
}

enum ScanFlag: String {
    case mismatch = "MIME Type Mismatch"
    case knownBad = "Known Bad Hash"
    case suspiciousExtension = "Suspicious Extension"
    case oversized = "File Too Large"
    case readError = "Cannot Read File"
}

// MARK: - SwiftUI Integration

struct AttachmentScannerView: View {
    @State private var selectedFile: URL?
    @State private var scanResult: ScanResult?
    @State private var isScanning = false
    @State private var showFilePicker = false

    var body: some View {
        VStack(spacing: 16) {
            if let result = scanResult {
                ScanResultView(result: result)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.badge.checkmark")
                        .font(.title)
                        .foregroundColor(.gray)

                    Text("Select a file to scan")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text("Check MIME type, magic bytes, and deny list")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
            }

            Button(action: { showFilePicker = true }) {
                Label("Choose File", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isScanning)
        }
        .padding()
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.data, .item],
            allowsMultipleSelection: false
        ) { result in
            guard let url = try? result.get().first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { return }
            isScanning = true
            scanResult = nil
            Task {
                let result = await AttachmentScanner.shared.scan(data, filename: url.lastPathComponent)
                await MainActor.run {
                    scanResult = result
                    isScanning = false
                }
            }
        }
    }
}

struct ScanResultView: View {
    let result: ScanResult

    var statusColor: Color {
        result.approved ? .green : .red
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: result.approved ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(statusColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.approved ? "Safe" : "Warning")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Flags: \(result.flags.count)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Spacer()
            }

            if !result.flags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(result.flags, id: \.rawValue) { flag in
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.yellow)
                            Text(flag.rawValue)
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding()
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Detected MIME")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                    Text(result.detectedMime.isEmpty ? "Unknown" : result.detectedMime)
                        .font(.caption)
                        .foregroundColor(.white)
                        .monospaced()
                }

                Divider()

                HStack {
                    Text("SHA-256")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                    Text(result.sha256.prefix(16) + "...")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .monospaced()
                }
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(8)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}
