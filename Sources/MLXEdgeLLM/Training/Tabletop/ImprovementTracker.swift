import Foundation
import SwiftUI

// MARK: - Improvement Plan Model

struct ImprovementPlan: Identifiable, Codable {
    let id = UUID()
    var title: String
    var description: String
    var assignedTo: String
    var deadline: Date
    var status: Status
}

enum Status: String, Codable {
    case pending
    case inProgress
    case completed
}

// MARK: - ImprovementTrackerViewModel

class ImprovementTrackerViewModel: ObservableObject {
    @Published var improvementPlans: [ImprovementPlan] = []
    
    init() {
        loadImprovementPlans()
    }
    
    func addImprovementPlan(_ plan: ImprovementPlan) {
        improvementPlans.append(plan)
        saveImprovementPlans()
    }
    
    func updateImprovementPlan(_ plan: ImprovementPlan) {
        if let index = improvementPlans.firstIndex(where: { $0.id == plan.id }) {
            improvementPlans[index] = plan
            saveImprovementPlans()
        }
    }
    
    func deleteImprovementPlan(_ plan: ImprovementPlan) {
        improvementPlans.removeAll { $0.id == plan.id }
        saveImprovementPlans()
    }
    
    private func loadImprovementPlans() {
        if let data = UserDefaults.standard.data(forKey: "ImprovementPlans"),
           let plans = try? JSONDecoder().decode([ImprovementPlan].self, from: data) {
            improvementPlans = plans
        }
    }
    
    private func saveImprovementPlans() {
        if let encoded = try? JSONEncoder().encode(improvementPlans) {
            UserDefaults.standard.set(encoded, forKey: "ImprovementPlans")
        }
    }
}

// MARK: - ImprovementTrackerView

struct ImprovementTrackerView: View {
    @StateObject private var viewModel = ImprovementTrackerViewModel()
    
    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.improvementPlans) { plan in
                    ImprovementPlanRow(plan: plan)
                        .onTapGesture {
                            // Navigate to detail view
                        }
                }
                .onDelete { indexSet in
                    indexSet.forEach { index in
                        viewModel.deleteImprovementPlan(viewModel.improvementPlans[index])
                    }
                }
            }
            .navigationTitle("Improvement Plans")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Navigate to add new plan view
                    }) {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
        }
    }
}

// MARK: - ImprovementPlanRow

struct ImprovementPlanRow: View {
    let plan: ImprovementPlan
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(plan.title)
                .font(.headline)
            Text(plan.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack {
                Text("Assigned to: \(plan.assignedTo)")
                Spacer()
                Text("Deadline: \(plan.deadline, style: .date)")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }
}

// MARK: - Previews

struct ImprovementTrackerView_Previews: PreviewProvider {
    static var previews: some View {
        ImprovementTrackerView()
    }
}