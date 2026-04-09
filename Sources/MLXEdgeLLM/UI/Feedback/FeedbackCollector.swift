import SwiftUI
import Foundation
import CoreLocation

// MARK: - Feedback Model

struct FeedbackItem: Identifiable, Codable {
    let id = UUID()
    var title: String
    var description: String
    var screenshots: [UIImage]
    var location: CLLocationCoordinate2D?
    var timestamp: Date
}

// MARK: - Feedback Service

class FeedbackService: ObservableObject {
    @Published private(set) var feedbackItems: [FeedbackItem] = []
    
    private let feedbackQueue = DispatchQueue(label: "com.zerodark.feedbackQueue", qos: .userInitiated)
    private let feedbackStoreURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("feedback.json")
    
    init() {
        loadFeedbackItems()
    }
    
    func addFeedback(title: String, description: String, screenshots: [UIImage], location: CLLocationCoordinate2D? = nil) {
        feedbackQueue.async {
            let newFeedback = FeedbackItem(title: title, description: description, screenshots: screenshots, location: location, timestamp: Date())
            self.feedbackItems.append(newFeedback)
            self.saveFeedbackItems()
        }
    }
    
    func removeFeedback(_ feedback: FeedbackItem) {
        feedbackQueue.async {
            self.feedbackItems.removeAll { $0.id == feedback.id }
            self.saveFeedbackItems()
        }
    }
    
    private func saveFeedbackItems() {
        do {
            let data = try JSONEncoder().encode(feedbackItems)
            try data.write(to: feedbackStoreURL)
        } catch {
            print("Failed to save feedback items: \(error)")
        }
    }
    
    private func loadFeedbackItems() {
        do {
            let data = try Data(contentsOf: feedbackStoreURL)
            feedbackItems = try JSONDecoder().decode([FeedbackItem].self, from: data)
        } catch {
            print("Failed to load feedback items: \(error)")
        }
    }
}

// MARK: - Feedback View Model

class FeedbackViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var description: String = ""
    @Published var screenshots: [UIImage] = []
    @Published var location: CLLocationCoordinate2D?
    
    @StateObject private var feedbackService: FeedbackService
    
    init(feedbackService: FeedbackService) {
        self.feedbackService = feedbackService
    }
    
    func addFeedback() {
        feedbackService.addFeedback(title: title, description: description, screenshots: screenshots, location: location)
        title = ""
        description = ""
        screenshots = []
        location = nil
    }
}

// MARK: - Feedback View

struct FeedbackView: View {
    @StateObject private var viewModel = FeedbackViewModel(feedbackService: FeedbackService())
    
    var body: some View {
        NavigationView {
            VStack {
                TextField("Title", text: $viewModel.title)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                
                TextEditor(text: $viewModel.description)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                
                Button(action: {
                    // Add screenshot logic here
                }) {
                    Text("Add Screenshot")
                }
                .padding()
                
                Button(action: {
                    viewModel.addFeedback()
                }) {
                    Text("Submit Feedback")
                }
                .padding()
            }
            .navigationTitle("Feedback")
        }
    }
}

// MARK: - Preview

struct FeedbackView_Previews: PreviewProvider {
    static var previews: some View {
        FeedbackView()
    }
}