import Foundation
import SwiftUI

// MARK: - LearningPath

struct LearningPath: Identifiable {
    let id = UUID()
    let title: String
    let courses: [Course]
}

// MARK: - Course

struct Course: Identifiable {
    let id = UUID()
    let title: String
    let prerequisites: [String]
}

// MARK: - LearningPathManager

class LearningPathManager: ObservableObject {
    @Published var learningPaths: [LearningPath] = []
    
    init() {
        setupLearningPaths()
    }
    
    private func setupLearningPaths() {
        let course1 = Course(title: "Introduction to ZeroDark", prerequisites: [])
        let course2 = Course(title: "Advanced AI Techniques", prerequisites: ["Introduction to ZeroDark"])
        let course3 = Course(title: "Field Simulation Basics", prerequisites: ["Introduction to ZeroDark"])
        let course4 = Course(title: "Tactical AI Strategies", prerequisites: ["Advanced AI Techniques", "Field Simulation Basics"])
        
        let path1 = LearningPath(title: "AI Specialist Path", courses: [course1, course2, course4])
        let path2 = LearningPath(title: "Simulation Engineer Path", courses: [course1, course3, course4])
        
        learningPaths = [path1, path2]
    }
}

// MARK: - LearningProgress

struct LearningProgress: Identifiable {
    let id = UUID()
    let course: Course
    let completed: Bool
}

// MARK: - ProgressDashboard

struct ProgressDashboard: View {
    @StateObject private var viewModel = LearningPathManager()
    @State private var selectedPath: LearningPath?
    
    var body: some View {
        NavigationView {
            List(viewModel.learningPaths) { path in
                Button(action: {
                    selectedPath = path
                }) {
                    Text(path.title)
                }
            }
            .navigationTitle("Learning Paths")
            .sheet(item: $selectedPath) { path in
                PathDetailView(path: path)
            }
        }
    }
}

// MARK: - PathDetailView

struct PathDetailView: View {
    let path: LearningPath
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(path.title)
                .font(.largeTitle)
                .padding()
            
            ForEach(path.courses) { course in
                CourseRow(course: course)
            }
        }
        .navigationTitle(path.title)
    }
}

// MARK: - CourseRow

struct CourseRow: View {
    let course: Course
    
    var body: some View {
        HStack {
            Text(course.title)
            Spacer()
            if course.prerequisites.isEmpty {
                Text("No Prerequisites")
            } else {
                Text("Prerequisites: \(course.prerequisites.joined(separator: ", "))")
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Preview

struct ProgressDashboard_Previews: PreviewProvider {
    static var previews: some View {
        ProgressDashboard()
    }
}