import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - FieldManualLoader

class FieldManualLoader: ObservableObject {
    @Published var manuals: [FieldManual] = []
    
    func loadManuals(from directory: URL) async {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for fileURL in fileURLs {
                if fileURL.pathExtension == "txt" {
                    if let manual = try await parseManual(from: fileURL) {
                        manuals.append(manual)
                    }
                }
            }
        } catch {
            print("Error loading manuals: \(error)")
        }
    }
    
    private func parseManual(from fileURL: URL) async throws -> FieldManual? {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let parser = ManualParser(content: content)
        return try await parser.parse()
    }
}

// MARK: - FieldManual

struct FieldManual {
    let title: String
    let chapters: [Chapter]
}

// MARK: - Chapter

struct Chapter {
    let title: String
    let sections: [Section]
}

// MARK: - Section

struct Section {
    let title: String
    let content: String
    let crossReferences: [String]
}

// MARK: - ManualParser

class ManualParser {
    private let content: String
    
    init(content: String) {
        self.content = content
    }
    
    func parse() async throws -> FieldManual {
        let lines = content.split(separator: "\n")
        var chapters: [Chapter] = []
        var currentChapter: Chapter?
        var currentSection: Section?
        
        for line in lines {
            if line.hasPrefix("# ") {
                if let currentSection = currentSection {
                    currentChapter?.sections.append(currentSection)
                }
                if let currentChapter = currentChapter {
                    chapters.append(currentChapter)
                }
                currentChapter = Chapter(title: String(line.dropFirst(2)), sections: [])
            } else if line.hasPrefix("## ") {
                if let currentSection = currentSection {
                    currentChapter?.sections.append(currentSection)
                }
                currentSection = Section(title: String(line.dropFirst(3)), content: "", crossReferences: [])
            } else if line.hasPrefix("### ") {
                if let currentSection = currentSection {
                    currentSection.content += "\(String(line.dropFirst(4)))\n"
                }
            } else if line.hasPrefix("#### ") {
                if let currentSection = currentSection {
                    currentSection.crossReferences.append(String(line.dropFirst(5)))
                }
            }
        }
        
        if let currentSection = currentSection {
            currentChapter?.sections.append(currentSection)
        }
        if let currentChapter = currentChapter {
            chapters.append(currentChapter)
        }
        
        return FieldManual(title: "Field Manual", chapters: chapters)
    }
}

// MARK: - FullTextSearch

class FullTextSearch {
    private let manuals: [FieldManual]
    
    init(manuals: [FieldManual]) {
        self.manuals = manuals
    }
    
    func search(query: String) -> [SearchResult] {
        let lowercasedQuery = query.lowercased()
        var results: [SearchResult] = []
        
        for manual in manuals {
            for chapter in manual.chapters {
                for section in chapter.sections {
                    if section.content.lowercased().contains(lowercasedQuery) {
                        results.append(SearchResult(manualTitle: manual.title, chapterTitle: chapter.title, sectionTitle: section.title, content: section.content))
                    }
                }
            }
        }
        
        return results
    }
}

// MARK: - SearchResult

struct SearchResult {
    let manualTitle: String
    let chapterTitle: String
    let sectionTitle: String
    let content: String
}