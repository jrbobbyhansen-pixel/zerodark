import Foundation
import SwiftUI

// MARK: - Training Log Model

struct TrainingSession: Identifiable, Codable {
    let id = UUID()
    let date: Date
    let topic: String
    let instructor: String
    let hours: Double
    var cpe: Double
    var ceu: Double
}

class TrainingLog: ObservableObject {
    @Published private(set) var sessions: [TrainingSession] = []
    
    init() {
        loadSessions()
    }
    
    func addSession(_ session: TrainingSession) {
        sessions.append(session)
        saveSessions()
    }
    
    func updateSession(_ session: TrainingSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
            saveSessions()
        }
    }
    
    func deleteSession(_ session: TrainingSession) {
        if let index = sessions.firstIndex(of: session) {
            sessions.remove(at: index)
            saveSessions()
        }
    }
    
    private func saveSessions() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(sessions) {
            UserDefaults.standard.set(encoded, forKey: "TrainingSessions")
        }
    }
    
    private func loadSessions() {
        if let savedSessions = UserDefaults.standard.data(forKey: "TrainingSessions"),
           let decodedSessions = try? JSONDecoder().decode([TrainingSession].self, from: savedSessions) {
            sessions = decodedSessions
        }
    }
}

// MARK: - Training Log View Model

class TrainingLogViewModel: ObservableObject {
    @Published var trainingLog: TrainingLog
    
    init(trainingLog: TrainingLog) {
        self.trainingLog = trainingLog
    }
    
    func addSession(_ session: TrainingSession) {
        trainingLog.addSession(session)
    }
    
    func updateSession(_ session: TrainingSession) {
        trainingLog.updateSession(session)
    }
    
    func deleteSession(_ session: TrainingSession) {
        trainingLog.deleteSession(session)
    }
}

// MARK: - Training Log View

struct TrainingLogView: View {
    @StateObject private var viewModel = TrainingLogViewModel(trainingLog: TrainingLog())
    
    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.trainingLog.sessions) { session in
                    TrainingSessionRow(session: session)
                }
                .onDelete { indexSet in
                    indexSet.forEach { index in
                        viewModel.deleteSession(viewModel.trainingLog.sessions[index])
                    }
                }
            }
            .navigationTitle("Training Log")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Add new session
                    }) {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
        }
    }
}

struct TrainingSessionRow: View {
    let session: TrainingSession
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(session.topic)
                .font(.headline)
            Text("Instructor: \(session.instructor)")
            Text("Hours: \(session.hours, specifier: "%.1f")")
            Text("CPE: \(session.cpe, specifier: "%.1f")")
            Text("CEU: \(session.ceu, specifier: "%.1f")")
        }
    }
}

// MARK: - Preview

struct TrainingLogView_Previews: PreviewProvider {
    static var previews: some View {
        TrainingLogView()
    }
}