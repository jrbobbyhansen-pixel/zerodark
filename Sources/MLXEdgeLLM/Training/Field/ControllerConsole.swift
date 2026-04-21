import SwiftUI
import Foundation
import CoreLocation

// MARK: - Models

struct ExerciseController {
    var id: UUID
    var name: String
    var location: CLLocationCoordinate2D
    var scenario: String
    var startTime: Date
    var endTime: Date
}

// MARK: - View Models

class ExerciseControllerViewModel: ObservableObject {
    @Published var controllers: [ExerciseController] = []
    @Published var selectedController: ExerciseController?
    
    func addController(name: String, location: CLLocationCoordinate2D, scenario: String, startTime: Date, endTime: Date) {
        let newController = ExerciseController(id: UUID(), name: name, location: location, scenario: scenario, startTime: startTime, endTime: endTime)
        controllers.append(newController)
    }
    
    func removeController(_ controller: ExerciseController) {
        if let index = controllers.firstIndex(of: controller) {
            controllers.remove(at: index)
        }
    }
}

// MARK: - Views

struct ControllerConsoleView: View {
    @StateObject private var viewModel = ExerciseControllerViewModel()
    
    var body: some View {
        List(viewModel.controllers) { controller in
                NavigationLink(value: controller) {
                    VStack(alignment: .leading) {
                        Text(controller.name)
                            .font(.headline)
                        Text(controller.scenario)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationDestination(for: ExerciseController.self) { controller in
                ControllerDetailView(controller: controller)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Add new controller logic
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
        .navigationTitle("Exercise Controllers")
    }
}

struct ControllerDetailView: View {
    let controller: ExerciseController
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(controller.name)
                .font(.largeTitle)
                .padding(.bottom)
            
            Text("Scenario: \(controller.scenario)")
                .font(.subheadline)
                .padding(.bottom)
            
            Text("Location: \(controller.location.latitude), \(controller.location.longitude)")
                .font(.subheadline)
                .padding(.bottom)
            
            Text("Start Time: \(controller.startTime, style: .date)")
                .font(.subheadline)
                .padding(.bottom)
            
            Text("End Time: \(controller.endTime, style: .date)")
                .font(.subheadline)
                .padding(.bottom)
        }
        .padding()
        .navigationTitle(controller.name)
    }
}

