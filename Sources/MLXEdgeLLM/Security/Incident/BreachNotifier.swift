import Foundation
import SwiftUI

// MARK: - BreachNotifier

class BreachNotifier: ObservableObject {
    @Published var breachDetected = false
    @Published var distributionList: [String] = []
    @Published var acknowledgmentList: [String] = []
    
    private let templateMessage = "Your account has been compromised. Please take immediate action to secure your account."
    
    func notifyAffectedParties() {
        distributionList.forEach { email in
            sendNotification(to: email)
        }
    }
    
    private func sendNotification(to email: String) {
        // Simulate sending a notification
        print("Notification sent to: \(email)")
        acknowledgmentList.append(email)
    }
    
    func acknowledgeNotification(by email: String) {
        if let index = acknowledgmentList.firstIndex(of: email) {
            acknowledgmentList.remove(at: index)
        }
    }
}

// MARK: - BreachNotificationView

struct BreachNotificationView: View {
    @StateObject private var notifier = BreachNotifier()
    
    var body: some View {
        VStack {
            Text("Breach Notification System")
                .font(.largeTitle)
                .padding()
            
            Button("Notify Affected Parties") {
                notifier.notifyAffectedParties()
            }
            .padding()
            .disabled(notifier.distributionList.isEmpty)
            
            List(notifier.acknowledgmentList, id: \.self) { email in
                HStack {
                    Text(email)
                    Spacer()
                    Button("Acknowledge") {
                        notifier.acknowledgeNotification(by: email)
                    }
                }
            }
            .padding()
        }
        .padding()
    }
}

// MARK: - Preview

struct BreachNotificationView_Previews: PreviewProvider {
    static var previews: some View {
        BreachNotificationView()
            .environmentObject(BreachNotifier())
    }
}