import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - Models

struct ChecklistItem: Identifiable {
    let id = UUID()
    var title: String
    var isCompleted: Bool = false
}

struct RehearsalChecklist: Identifiable {
    let id = UUID()
    var title: String
    var items: [ChecklistItem]
}

// MARK: - ViewModel

class RehearsalChecklistViewModel: ObservableObject {
    @Published var checklists: [RehearsalChecklist] = []
    @Published var selectedChecklist: RehearsalChecklist?
    
    func addChecklist(_ checklist: RehearsalChecklist) {
        checklists.append(checklist)
    }
    
    func toggleCompletion(for item: ChecklistItem, in checklist: RehearsalChecklist) {
        if let index = checklist.items.firstIndex(where: { $0.id == item.id }) {
            var updatedChecklist = checklist
            updatedChecklist.items[index].isCompleted.toggle()
            if let checklistIndex = checklists.firstIndex(where: { $0.id == checklist.id }) {
                checklists[checklistIndex] = updatedChecklist
            }
        }
    }
    
    func flagIncompleteItems(in checklist: RehearsalChecklist) -> [ChecklistItem] {
        return checklist.items.filter { !$0.isCompleted }
    }
}

// MARK: - Views

struct RehearsalChecklistView: View {
    @StateObject private var viewModel = RehearsalChecklistViewModel()
    
    var body: some View {
        NavigationView {
            List(viewModel.checklists) { checklist in
                Section(header: Text(checklist.title)) {
                    ForEach(checklist.items) { item in
                        HStack {
                            Text(item.title)
                            Spacer()
                            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(item.isCompleted ? .green : .red)
                                .onTapGesture {
                                    viewModel.toggleCompletion(for: item, in: checklist)
                                }
                        }
                    }
                }
            }
            .navigationTitle("Rehearsal Checklists")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Add new checklist logic here
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

// MARK: - Previews

struct RehearsalChecklistView_Previews: PreviewProvider {
    static var previews: some View {
        RehearsalChecklistView()
    }
}