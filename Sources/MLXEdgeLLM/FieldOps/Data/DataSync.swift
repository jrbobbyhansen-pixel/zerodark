import Foundation
import SwiftUI

// MARK: - DataSync

class DataSync: ObservableObject {
    @Published var localData: [DataItem] = []
    @Published var remoteData: [DataItem] = []
    @Published var syncStatus: SyncStatus = .idle

    private let networkService: NetworkService
    private let conflictResolver: ConflictResolver

    init(networkService: NetworkService, conflictResolver: ConflictResolver) {
        self.networkService = networkService
        self.conflictResolver = conflictResolver
    }

    func syncData() async {
        syncStatus = .inProgress
        do {
            let remoteItems = try await networkService.fetchRemoteData()
            remoteData = remoteItems
            let resolvedData = conflictResolver.resolveConflicts(localData: localData, remoteData: remoteItems)
            localData = resolvedData
            try await networkService.uploadData(data: localData)
            syncStatus = .completed
        } catch {
            syncStatus = .failed(error: error)
        }
    }

    func partialSync(items: [DataItem]) async {
        syncStatus = .inProgress
        do {
            let remoteItems = try await networkService.fetchRemoteData()
            remoteData = remoteItems
            let resolvedData = conflictResolver.resolveConflicts(localData: items, remoteData: remoteItems)
            localData.append(contentsOf: resolvedData)
            try await networkService.uploadData(data: localData)
            syncStatus = .completed
        } catch {
            syncStatus = .failed(error: error)
        }
    }
}

// MARK: - DataItem

struct DataItem: Identifiable, Codable {
    let id: UUID
    let content: String
    let timestamp: Date
}

// MARK: - SyncStatus

enum SyncStatus {
    case idle
    case inProgress
    case completed
    case failed(error: Error)
}

// MARK: - NetworkService

protocol NetworkService {
    func fetchRemoteData() async throws -> [DataItem]
    func uploadData(data: [DataItem]) async throws
}

// MARK: - ConflictResolver

protocol ConflictResolver {
    func resolveConflicts(localData: [DataItem], remoteData: [DataItem]) -> [DataItem]
}

// MARK: - DefaultNetworkService

class DefaultNetworkService: NetworkService {
    func fetchRemoteData() async throws -> [DataItem] {
        // Simulate network call
        return []
    }

    func uploadData(data: [DataItem]) async throws {
        // Simulate network call
    }
}

// MARK: - DefaultConflictResolver

class DefaultConflictResolver: ConflictResolver {
    func resolveConflicts(localData: [DataItem], remoteData: [DataItem]) -> [DataItem] {
        // Simple conflict resolution: keep local data
        return localData
    }
}