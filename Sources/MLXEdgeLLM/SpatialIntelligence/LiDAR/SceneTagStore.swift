// SceneTagStore.swift — Manages SceneTag persistence alongside LiDAR scan data
// Stores scene_tag.json files in Documents/LiDARScans/<scanId>/

import Foundation

@MainActor
final class SceneTagStore: ObservableObject {
    static let shared = SceneTagStore()

    @Published private(set) var tags: [SceneTag] = []

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        loadAll()
    }

    // MARK: - Scan Directory

    private var scansDir: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiDARScans", isDirectory: true)
    }

    private func scanDir(for id: UUID) -> URL {
        scansDir.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func tagURL(for id: UUID) -> URL {
        scanDir(for: id).appendingPathComponent("scene_tag.json")
    }

    // MARK: - CRUD

    func save(_ tag: SceneTag) {
        guard let data = try? encoder.encode(tag) else { return }
        let url = tagURL(for: tag.id)
        try? data.write(to: url, options: .atomic)

        if let idx = tags.firstIndex(where: { $0.id == tag.id }) {
            tags[idx] = tag
        } else {
            tags.append(tag)
        }
    }

    func load(for id: UUID) -> SceneTag? {
        let url = tagURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(SceneTag.self, from: data)
    }

    func delete(id: UUID) {
        let url = tagURL(for: id)
        try? fileManager.removeItem(at: url)
        tags.removeAll { $0.id == id }
    }

    func loadAll() {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: scansDir, includingPropertiesForKeys: nil
        ) else {
            tags = []
            return
        }

        tags = contents.compactMap { dirURL in
            let tagFile = dirURL.appendingPathComponent("scene_tag.json")
            guard let data = try? Data(contentsOf: tagFile) else { return nil }
            return try? decoder.decode(SceneTag.self, from: data)
        }.sorted { $0.timestamp > $1.timestamp }
    }

    func update(_ id: UUID, mutate: (inout SceneTag) -> Void) {
        guard var tag = load(for: id) ?? tags.first(where: { $0.id == id }) else { return }
        mutate(&tag)
        save(tag)
    }
}
