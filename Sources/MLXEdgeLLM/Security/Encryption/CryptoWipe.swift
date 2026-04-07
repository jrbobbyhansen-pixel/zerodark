import Foundation
import SwiftUI

// MARK: - CryptoWipeService

class CryptoWipeService: ObservableObject {
    @Published private(set) var isWiping = false
    @Published private(set) var wipeCompleted = false
    @Published private(set) var error: Error?

    private let keychainService: KeychainService
    private let fileSystemService: FileSystemService

    init(keychainService: KeychainService, fileSystemService: FileSystemService) {
        self.keychainService = keychainService
        self.fileSystemService = fileSystemService
    }

    func activateEmergencyWipe() {
        Task {
            await wipeData()
        }
    }

    private func wipeData() async {
        isWiping = true
        wipeCompleted = false
        error = nil

        do {
            try await keychainService.deleteAllKeys()
            try await fileSystemService.deleteAllEncryptedFiles()
            wipeCompleted = true
        } catch {
            self.error = error
        } finally {
            isWiping = false
        }
    }
}

// MARK: - KeychainService

actor KeychainService {
    func deleteAllKeys() async throws {
        // Simulate keychain deletion
        // In a real implementation, this would delete all keys from the keychain
        print("All keys deleted from keychain")
    }
}

// MARK: - FileSystemService

actor FileSystemService {
    func deleteAllEncryptedFiles() async throws {
        // Simulate file deletion
        // In a real implementation, this would delete all encrypted files from the file system
        print("All encrypted files deleted")
    }
}

// MARK: - CryptoWipeView

struct CryptoWipeView: View {
    @StateObject private var viewModel = CryptoWipeViewModel()

    var body: some View {
        VStack {
            Text("Emergency Crypto Wipe")
                .font(.largeTitle)
                .padding()

            Button(action: viewModel.activateWipe) {
                Text("Activate Wipe")
                    .font(.headline)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(viewModel.isWiping)

            if viewModel.isWiping {
                ProgressView("Wiping Data...")
            }

            if viewModel.wipeCompleted {
                Text("Wipe Completed Successfully")
                    .foregroundColor(.green)
            }

            if let error = viewModel.error {
                Text("Error: \(error.localizedDescription)")
                    .foregroundColor(.red)
            }
        }
        .padding()
    }
}

// MARK: - CryptoWipeViewModel

class CryptoWipeViewModel: ObservableObject {
    @Published private(set) var isWiping = false
    @Published private(set) var wipeCompleted = false
    @Published private(set) var error: Error?

    private let cryptoWipeService: CryptoWipeService

    init(cryptoWipeService: CryptoWipeService = CryptoWipeService(keychainService: KeychainService(), fileSystemService: FileSystemService())) {
        self.cryptoWipeService = cryptoWipeService
        setupObservers()
    }

    func activateWipe() {
        cryptoWipeService.activateEmergencyWipe()
    }

    private func setupObservers() {
        cryptoWipeService.$isWiping
            .sink { [weak self] isWiping in
                self?.isWiping = isWiping
            }
            .store(in: &cancellables)

        cryptoWipeService.$wipeCompleted
            .sink { [weak self] wipeCompleted in
                self?.wipeCompleted = wipeCompleted
            }
            .store(in: &cancellables)

        cryptoWipeService.$error
            .sink { [weak self] error in
                self?.error = error
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()
}