import Foundation
import SwiftUI
import CryptoKit

// MARK: - SecureFileTransfer

class SecureFileTransfer: ObservableObject {
    @Published var transferState: TransferState = .idle
    @Published var progress: Double = 0.0
    @Published var error: Error?

    private let chunkSize: Int = 1024 * 1024 // 1 MB
    private var fileURL: URL
    private var fileHandle: FileHandle?
    private var encryptedData: Data = Data()
    private var transferTask: Task<Void, Never>?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    deinit {
        cancelTransfer()
    }

    func startTransfer() {
        guard transferState == .idle else { return }
        transferState = .transferring
        transferTask = Task {
            do {
                try await transferFile()
                transferState = .completed
            } catch {
                error = error
                transferState = .failed
            }
        }
    }

    func cancelTransfer() {
        transferTask?.cancel()
        transferTask = nil
        transferState = .idle
        fileHandle?.closeFile()
        fileHandle = nil
        encryptedData.removeAll()
    }

    private func transferFile() async throws {
        fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { fileHandle?.closeFile() }

        let fileSize = fileHandle!.seekToEndOfFile()
        fileHandle!.seek(toFileOffset: 0)

        var offset: Int64 = 0
        while offset < fileSize {
            let chunk = try fileHandle!.read(upToCount: chunkSize)
            guard let chunkData = chunk else { break }

            let encryptedChunk = try encryptChunk(chunkData)
            // Simulate sending chunk over network
            try await simulateNetworkTransfer(encryptedChunk)

            offset += Int64(chunkData.count)
            progress = Double(offset) / Double(fileSize)
        }
    }

    private func encryptChunk(_ chunk: Data) throws -> Data {
        let key = SymmetricKey(size: .aes256)
        let sealedBox = try AES.GCM.seal(chunk, using: key)
        return sealedBox.ciphertext
    }

    private func simulateNetworkTransfer(_ chunk: Data) async throws {
        // Simulate network delay
        try await Task.sleep(nanoseconds: UInt64.random(in: 100_000_000...500_000_000))
    }
}

// MARK: - TransferState

enum TransferState {
    case idle
    case transferring
    case completed
    case failed
}