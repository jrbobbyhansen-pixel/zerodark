import Foundation
import SwiftUI
import CoreLocation

// MARK: - CheckInSystem

class CheckInSystem: ObservableObject {
    @Published var checkIns: [CheckIn] = []
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var isCheckInScheduled: Bool = false
    @Published var scheduledCheckInTime: Date?
    
    private let locationManager = CLLocationManager()
    private let notificationCenter = UNUserNotificationCenter.current()
    
    init() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        
        notificationCenter.delegate = self
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification authorization failed: \(error)")
            }
        }
    }
    
    func scheduleCheckIn(at time: Date) {
        scheduledCheckInTime = time
        isCheckInScheduled = true
        scheduleLocalNotification(at: time)
    }
    
    func cancelScheduledCheckIn() {
        scheduledCheckInTime = nil
        isCheckInScheduled = false
        cancelLocalNotification()
    }
    
    func checkIn(with status: String) {
        guard let currentLocation = currentLocation else { return }
        let checkIn = CheckIn(location: currentLocation, status: status, timestamp: Date())
        checkIns.append(checkIn)
        saveCheckIns()
    }
    
    private func scheduleLocalNotification(at time: Date) {
        let content = UNMutableNotificationContent()
        content.title = "ZeroDark Check-In"
        content.body = "It's time to check in with your team!"
        content.sound = UNNotificationSound.default
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: time), repeats: false)
        
        let request = UNNotificationRequest(identifier: "CheckInNotification", content: content, trigger: trigger)
        notificationCenter.add(request)
    }
    
    private func cancelLocalNotification() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ["CheckInNotification"])
    }
    
    private func saveCheckIns() {
        // Implement saving check-ins to persistent storage
    }
}

// MARK: - CheckIn

struct CheckIn: Identifiable {
    let id = UUID()
    let location: CLLocationCoordinate2D
    let status: String
    let timestamp: Date
}

// MARK: - CLLocationManagerDelegate

extension CheckInSystem: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location.coordinate
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension CheckInSystem: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.alert, .sound])
    }
}

// MARK: - CheckInView

struct CheckInView: View {
    @StateObject private var checkInSystem = CheckInSystem()
    
    var body: some View {
        VStack {
            if let currentLocation = checkInSystem.currentLocation {
                Text("Current Location: \(currentLocation.latitude), \(currentLocation.longitude)")
            } else {
                Text("Location not available")
            }
            
            TextField("Status", text: $status)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            Button(action: {
                checkInSystem.checkIn(with: status)
            }) {
                Text("Check In")
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            
            if checkInSystem.isCheckInScheduled {
                Text("Scheduled Check-In: \(checkInSystem.scheduledCheckInTime?.formatted(date: .long, time: .short) ?? "N/A")")
            } else {
                Button(action: {
                    let scheduledTime = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
                    checkInSystem.scheduleCheckIn(at: scheduledTime)
                }) {
                    Text("Schedule Check-In")
                }
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
        .padding()
        .navigationTitle("Team Check-In")
    }
    
    @State private var status = ""
}

// MARK: - Preview

struct CheckInView_Previews: PreviewProvider {
    static var previews: some View {
        CheckInView()
    }
}