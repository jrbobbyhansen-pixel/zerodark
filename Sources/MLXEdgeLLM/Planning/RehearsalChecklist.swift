// RehearsalChecklist.swift — Pre-mission checklist with templates + persistence

import Foundation
import SwiftUI

// MARK: - Models

struct ChecklistItem: Identifiable, Codable {
    let id: UUID
    var title: String
    var isCompleted: Bool

    init(title: String, isCompleted: Bool = false) {
        self.id = UUID()
        self.title = title
        self.isCompleted = isCompleted
    }
}

struct RehearsalChecklist: Identifiable, Codable {
    let id: UUID
    var title: String
    var items: [ChecklistItem]

    init(title: String, items: [ChecklistItem]) {
        self.id = UUID()
        self.title = title
        self.items = items
    }

    var completionPercent: Double {
        guard !items.isEmpty else { return 0 }
        return Double(items.filter(\.isCompleted).count) / Double(items.count) * 100
    }

    var isComplete: Bool { items.allSatisfy(\.isCompleted) }
}

// MARK: - Templates

private let checklistTemplates: [RehearsalChecklist] = [
    RehearsalChecklist(title: "Movement Checklist", items: [
        ChecklistItem(title: "Route planned and briefed"),
        ChecklistItem(title: "Alternate routes identified"),
        ChecklistItem(title: "Rally points designated"),
        ChecklistItem(title: "Pace count established"),
        ChecklistItem(title: "Map and compass available"),
        ChecklistItem(title: "GPS batteries charged"),
        ChecklistItem(title: "Night movement plan if applicable"),
        ChecklistItem(title: "Communication check completed"),
    ]),
    RehearsalChecklist(title: "Medical Checklist", items: [
        ChecklistItem(title: "IFAK inspected and complete"),
        ChecklistItem(title: "Tourniquets accessible (2 per person)"),
        ChecklistItem(title: "TCCC card on person"),
        ChecklistItem(title: "Casualty collection point identified"),
        ChecklistItem(title: "MEDEVAC 9-line pre-formatted"),
        ChecklistItem(title: "Allergies documented per team member"),
        ChecklistItem(title: "Medications inventoried"),
    ]),
    RehearsalChecklist(title: "Communications Checklist", items: [
        ChecklistItem(title: "Primary freq programmed and tested"),
        ChecklistItem(title: "Alternate freq programmed"),
        ChecklistItem(title: "Mesh devices charged and paired"),
        ChecklistItem(title: "Radio check with all stations"),
        ChecklistItem(title: "Call signs assigned and briefed"),
        ChecklistItem(title: "Challenge/password set"),
        ChecklistItem(title: "Emergency freq identified (155.340)"),
    ]),
    RehearsalChecklist(title: "Shelter Checklist", items: [
        ChecklistItem(title: "Shelter site identified"),
        ChecklistItem(title: "Tarp or poncho available"),
        ChecklistItem(title: "550 cord / rope packed"),
        ChecklistItem(title: "Ground insulation planned"),
        ChecklistItem(title: "Fire-making materials (lighter, ferro rod)"),
        ChecklistItem(title: "Water procurement plan"),
        ChecklistItem(title: "Security perimeter established"),
    ]),
]

// MARK: - ViewModel

@MainActor
final class RehearsalChecklistViewModel: ObservableObject {
    @Published var checklists: [RehearsalChecklist] = []

    private let persistURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("checklists.json")
    }()

    init() { load() }

    func addTemplate(_ template: RehearsalChecklist) {
        // Create a fresh copy with new IDs
        let fresh = RehearsalChecklist(
            title: template.title,
            items: template.items.map { ChecklistItem(title: $0.title) }
        )
        checklists.append(fresh)
        save()
    }

    func toggleItem(checklistID: UUID, itemID: UUID) {
        guard let ci = checklists.firstIndex(where: { $0.id == checklistID }),
              let ii = checklists[ci].items.firstIndex(where: { $0.id == itemID }) else { return }
        checklists[ci].items[ii].isCompleted.toggle()
        save()
    }

    func removeChecklist(at offsets: IndexSet) {
        checklists.remove(atOffsets: offsets)
        save()
    }

    func share(_ checklist: RehearsalChecklist) {
        var text = "\(checklist.title)\n"
        text += String(repeating: "═", count: checklist.title.count) + "\n\n"
        for item in checklist.items {
            let mark = item.isCompleted ? "[x]" : "[ ]"
            text += "\(mark) \(item.title)\n"
        }
        text += "\nCompletion: \(String(format: "%.0f", checklist.completionPercent))%\n"

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("checklist.txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.rootViewController?
            .present(av, animated: true)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(checklists) else { return }
        try? data.write(to: persistURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: persistURL),
              let loaded = try? JSONDecoder().decode([RehearsalChecklist].self, from: data) else { return }
        checklists = loaded
    }
}

// MARK: - RehearsalChecklistView

struct RehearsalChecklistView: View {
    @StateObject private var vm = RehearsalChecklistViewModel()
    @State private var showTemplates = false

    var body: some View {
        Form {
            // Active checklists
            if !vm.checklists.isEmpty {
                ForEach(vm.checklists) { checklist in
                    Section {
                        HStack {
                            Text(checklist.title).font(.headline)
                            Spacer()
                            Text("\(String(format: "%.0f", checklist.completionPercent))%")
                                .font(.caption.bold())
                                .foregroundColor(checklist.isComplete ? .green : .secondary)
                        }
                        ProgressView(value: checklist.completionPercent, total: 100)
                            .tint(checklist.isComplete ? .green : ZDDesign.cyanAccent)

                        ForEach(checklist.items) { item in
                            Button {
                                vm.toggleItem(checklistID: checklist.id, itemID: item.id)
                            } label: {
                                HStack {
                                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(item.isCompleted ? .green : .secondary)
                                    Text(item.title)
                                        .strikethrough(item.isCompleted)
                                        .foregroundColor(item.isCompleted ? .secondary : .primary)
                                }
                            }
                        }

                        Button {
                            vm.share(checklist)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(.caption)
                        }
                    }
                }
                .onDelete { vm.removeChecklist(at: $0) }
            }

            // Add from template
            Section("Templates") {
                ForEach(checklistTemplates) { template in
                    Button {
                        vm.addTemplate(template)
                    } label: {
                        Label(template.title, systemImage: "doc.on.clipboard")
                    }
                }
            }
        }
        .navigationTitle("Checklists")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack { RehearsalChecklistView() }
}
