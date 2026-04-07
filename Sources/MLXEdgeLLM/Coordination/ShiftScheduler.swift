import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - ShiftScheduler

class ShiftScheduler: ObservableObject {
    @Published var shifts: [Shift] = []
    @Published var restDebt: [String: Int] = [:]
    @Published var fatigueRisk: [String: Double] = [:]
    
    private let notificationService: NotificationService
    
    init(notificationService: NotificationService) {
        self.notificationService = notificationService
    }
    
    func addShift(shift: Shift) {
        shifts.append(shift)
        updateRestDebtAndFatigueRisk()
    }
    
    func removeShift(shift: Shift) {
        if let index = shifts.firstIndex(of: shift) {
            shifts.remove(at: index)
            updateRestDebtAndFatigueRisk()
        }
    }
    
    private func updateRestDebtAndFatigueRisk() {
        // Calculate rest debt and fatigue risk based on current shifts
        // This is a placeholder implementation
        restDebt = shifts.reduce(into: [:]) { result, shift in
            result[shift.teamMember, default: 0] += shift.duration
        }
        
        fatigueRisk = shifts.reduce(into: [:]) { result, shift in
            result[shift.teamMember, default: 0.0] += shift.duration * 0.1
        }
    }
}

// MARK: - Shift

struct Shift: Identifiable, Equatable {
    let id = UUID()
    let teamMember: String
    let startTime: Date
    let duration: Int // in hours
}

// MARK: - NotificationService

class NotificationService {
    func notifyTeamMember(teamMember: String, message: String) {
        // Implementation to send notification to team member
        print("Notification sent to \(teamMember): \(message)")
    }
}

// MARK: - ShiftSchedulerView

struct ShiftSchedulerView: View {
    @StateObject private var viewModel = ShiftScheduler(notificationService: NotificationService())
    
    var body: some View {
        VStack {
            List(viewModel.shifts) { shift in
                Text("\(shift.teamMember) - \(shift.startTime, style: .date) - \(shift.duration) hours")
            }
            
            Button("Add Shift") {
                // Add shift logic here
            }
            
            Button("Remove Shift") {
                // Remove shift logic here
            }
        }
        .padding()
    }
}

// MARK: - Preview

struct ShiftSchedulerView_Previews: PreviewProvider {
    static var previews: some View {
        ShiftSchedulerView()
    }
}