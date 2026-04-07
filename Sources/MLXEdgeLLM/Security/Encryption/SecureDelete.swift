import Foundation
import SwiftUI

// MARK: - SecureDelete

class SecureDelete: ObservableObject {
    @Published var isDeleting = false
    @Published var deletionProgress: Double = 0.0
    @Published var deletionError: Error?

    private let fileManager = FileManager.default
    private var deletionTask: Task<Void, Never>?

    func secureDelete(fileURL: URL, passes: Int = 3, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !isDeleting else {
            completion(.failure(SecureDeleteError.alreadyDeleting))
            return
        }

        isDeleting = true
        deletionProgress = 0.0
        deletionError = nil

        deletionTask = Task {
            do {
                try await overwriteFile(fileURL: fileURL, passes: passes)
                try await fileManager.removeItem(at: fileURL)
                completion(.success(()))
            } catch {
                deletionError = error
                completion(.failure(error))
            } finally {
                isDeleting = false
            }
        }
    }

    func cancelDeletion() {
        deletionTask?.cancel()
        deletionTask = nil
        isDeleting = false
    }

    private func overwriteFile(fileURL: URL, passes: Int) async throws {
        let fileSize = try fileManager.attributesOfItem(atPath: fileURL.path)[.size] as! Int
        let data = Data(count: fileSize)

        for pass in 1...passes {
            try await Task.sleep(nanoseconds: UInt64.random(in: 100_000_000...500_000_000))
            try data.write(to: fileURL, options: .atomic)
            deletionProgress = Double(pass) / Double(passes)
        }
    }
}

// MARK: - SecureDeleteError

enum SecureDeleteError: Error, LocalizedError {
    case alreadyDeleting

    var errorDescription: String? {
        switch self {
        case .alreadyDeleting:
            return "A deletion is already in progress."
        }
    }
}

// MARK: - SecureDeleteView

struct SecureDeleteView: View {
    @StateObject private var secureDelete = SecureDelete()
    @State private var fileURL: URL?
    @State private var passes = 3
    @State private var showCompletionAlert = false

    var body: some View {
        VStack {
            Button("Select File") {
                let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.data])
                documentPicker.delegate = self
                present(documentPicker, animated: true)
            }
            .padding()

            if let fileURL {
                Text("Selected File: \(fileURL.lastPathComponent)")
            }

            Stepper("Passes: \(passes)", value: $passes, in: 1...10)
                .padding()

            Button("Secure Delete") {
                secureDelete.secureDelete(fileURL: fileURL, passes: passes) { result in
                    switch result {
                    case .success:
                        showCompletionAlert = true
                    case .failure(let error):
                        print("Deletion failed: \(error.localizedDescription)")
                    }
                }
            }
            .disabled(secureDelete.isDeleting || fileURL == nil)
            .padding()

            if secureDelete.isDeleting {
                ProgressView(value: secureDelete.deletionProgress)
                    .padding()
            }

            if let error = secureDelete.deletionError {
                Text("Error: \(error.localizedDescription)")
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .alert(isPresented: $showCompletionAlert) {
            Alert(title: Text("Success"), message: Text("File has been securely deleted."), dismissButton: .default(Text("OK")))
        }
    }
}

// MARK: - UIDocumentPickerDelegate

extension SecureDeleteView: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        fileURL = urls.first
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // Handle cancellation if needed
    }
}