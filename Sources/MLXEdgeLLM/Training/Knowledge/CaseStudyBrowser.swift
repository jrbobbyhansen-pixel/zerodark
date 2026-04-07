import SwiftUI
import Foundation

// MARK: - Case Study Model

struct CaseStudy: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let incidentDate: Date
    let location: CLLocationCoordinate2D
    let lessonsLearned: [String]
    let discussionQuestions: [String]
}

// MARK: - CaseStudyBrowserViewModel

class CaseStudyBrowserViewModel: ObservableObject {
    @Published var caseStudies: [CaseStudy] = []
    
    init() {
        loadCaseStudies()
    }
    
    private func loadCaseStudies() {
        // Simulate loading case studies from a data source
        caseStudies = [
            CaseStudy(
                title: "Operation Stormfront",
                description: "A tactical operation in a high-risk urban environment.",
                incidentDate: Date(timeIntervalSince1970: 1672531200), // Example date
                location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // San Francisco
                lessonsLearned: ["Communication is key", "Adaptability is crucial"],
                discussionQuestions: ["What could have been done differently?", "How would you handle a similar situation?"]
            ),
            CaseStudy(
                title: "Operation Echo",
                description: "A covert operation in a dense forest.",
                incidentDate: Date(timeIntervalSince1970: 1675209600), // Example date
                location: CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321), // Seattle
                lessonsLearned: ["Surveillance is essential", "Teamwork is vital"],
                discussionQuestions: ["What challenges did you face?", "How did you overcome them?"]
            )
        ]
    }
}

// MARK: - CaseStudyBrowserView

struct CaseStudyBrowserView: View {
    @StateObject private var viewModel = CaseStudyBrowserViewModel()
    
    var body: some View {
        NavigationView {
            List(viewModel.caseStudies) { caseStudy in
                NavigationLink(destination: CaseStudyDetailView(caseStudy: caseStudy)) {
                    VStack(alignment: .leading) {
                        Text(caseStudy.title)
                            .font(.headline)
                        Text(caseStudy.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Case Studies")
        }
    }
}

// MARK: - CaseStudyDetailView

struct CaseStudyDetailView: View {
    let caseStudy: CaseStudy
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(caseStudy.title)
                .font(.largeTitle)
                .padding(.bottom)
            
            Text("Incident Date: \(caseStudy.incidentDate, formatter: DateFormatter.localizedString(from: caseStudy.incidentDate, dateStyle: .medium, timeStyle: .none))")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Location: \(caseStudy.location.latitude), \(caseStudy.location.longitude)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Section(header: Text("Lessons Learned")) {
                ForEach(caseStudy.lessonsLearned, id: \.self) { lesson in
                    Text(lesson)
                }
            }
            
            Section(header: Text("Discussion Questions")) {
                ForEach(caseStudy.discussionQuestions, id: \.self) { question in
                    Text(question)
                }
            }
        }
        .padding()
        .navigationTitle(caseStudy.title)
    }
}

// MARK: - Preview

struct CaseStudyBrowserView_Previews: PreviewProvider {
    static var previews: some View {
        CaseStudyBrowserView()
    }
}