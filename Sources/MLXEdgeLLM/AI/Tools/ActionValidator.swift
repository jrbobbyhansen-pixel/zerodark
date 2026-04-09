import Foundation
import SwiftUI
import CoreLocation

// MARK: - ActionValidator

class ActionValidator: ObservableObject {
    @Published var isValid: Bool = false
    @Published var errorMessage: String = ""
    
    func validate(action: ProposedAction) async -> Bool {
        switch action {
        case .moveToLocation(let location):
            return await validateMoveToLocation(location)
        case .takePhoto:
            return await validateTakePhoto()
        case .sendAlert(let message):
            return await validateSendAlert(message)
        }
    }
    
    private func validateMoveToLocation(_ location: CLLocationCoordinate2D) async -> Bool {
        // Example constraint: Ensure the location is within a certain radius
        let currentLocation = CLLocationManager().location?.coordinate ?? CLLocationCoordinate2D()
        let distance = currentLocation.distance(from: location)
        
        if distance > 1000 { // 1 km
            errorMessage = "Location is too far away."
            return false
        }
        
        isValid = true
        return true
    }
    
    private func validateTakePhoto() async -> Bool {
        // Example constraint: Ensure the device has a camera
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            errorMessage = "Device does not have a camera."
            return false
        }
        
        isValid = true
        return true
    }
    
    private func validateSendAlert(_ message: String) async -> Bool {
        // Example constraint: Ensure the message is not empty
        guard !message.isEmpty else {
            errorMessage = "Alert message cannot be empty."
            return false
        }
        
        isValid = true
        return true
    }
}

// MARK: - ProposedAction

enum ProposedAction {
    case moveToLocation(CLLocationCoordinate2D)
    case takePhoto
    case sendAlert(String)
}

// MARK: - Example SwiftUI View

struct ActionValidationView: View {
    @StateObject private var validator = ActionValidator()
    @State private var action: ProposedAction?
    
    var body: some View {
        VStack {
            Button("Move to Location") {
                action = .moveToLocation(CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194))
            }
            
            Button("Take Photo") {
                action = .takePhoto
            }
            
            Button("Send Alert") {
                action = .sendAlert("This is an alert message.")
            }
            
            if let action = action {
                Button("Validate Action") {
                    Task {
                        let isValid = await validator.validate(action: action)
                        if !isValid {
                            print("Validation failed: \(validator.errorMessage)")
                        } else {
                            print("Action is valid.")
                        }
                    }
                }
            }
        }
        .padding()
    }
}

struct ActionValidationView_Previews: PreviewProvider {
    static var previews: some View {
        ActionValidationView()
    }
}