import Foundation
import SwiftUI
import CoreLocation

// MARK: - TakMissionSync

class TakMissionSync: ObservableObject {
    @Published var missionData: MissionData?
    @Published var syncStatus: SyncStatus = .idle
    @Published var error: Error?

    private let networkManager: NetworkManager
    private let fileManager: FileManager

    init(networkManager: NetworkManager = NetworkManager(), fileManager: FileManager = .default) {
        self.networkManager = networkManager
        self.fileManager = fileManager
    }

    func downloadMissionData(missionID: String) async {
        syncStatus = .downloading
        do {
            let data = try await networkManager.downloadMissionData(missionID: missionID)
            missionData = try JSONDecoder().decode(MissionData.self, from: data)
            syncStatus = .idle
        } catch {
            error = error
            syncStatus = .idle
        }
    }

    func uploadContribution(missionID: String, contribution: Contribution) async {
        syncStatus = .uploading
        do {
            let jsonData = try JSONEncoder().encode(contribution)
            try await networkManager.uploadContribution(missionID: missionID, data: jsonData)
            syncStatus = .idle
        } catch {
            error = error
            syncStatus = .idle
        }
    }
}

// MARK: - SyncStatus

enum SyncStatus {
    case idle
    case downloading
    case uploading
}

// MARK: - MissionData

struct MissionData: Codable {
    let missionID: String
    let title: String
    let description: String
    let objectives: [Objective]
}

// MARK: - Objective

struct Objective: Codable {
    let objectiveID: String
    let description: String
    let location: CLLocationCoordinate2D
}

// MARK: - Contribution

struct Contribution: Codable {
    let contributorID: String
    let timestamp: Date
    let details: String
}

// MARK: - NetworkManager

actor NetworkManager {
    func downloadMissionData(missionID: String) async throws -> Data {
        // Simulate network request
        try await Task.sleep(for: .seconds(2))
        guard let url = URL(string: "https://example.com/api/missions/\(missionID)/data") else {
            throw NSError(domain: "Invalid URL", code: 400, userInfo: nil)
        }
        let (data, _) = try await PinnedURLSession.shared.session.data(from: url)
        return data
    }

    func uploadContribution(missionID: String, data: Data) async throws {
        // Simulate network request
        try await Task.sleep(for: .seconds(2))
        guard let url = URL(string: "https://example.com/api/missions/\(missionID)/contributions") else {
            throw NSError(domain: "Invalid URL", code: 400, userInfo: nil)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await PinnedURLSession.shared.session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "Upload failed", code: 500, userInfo: nil)
        }
    }
}