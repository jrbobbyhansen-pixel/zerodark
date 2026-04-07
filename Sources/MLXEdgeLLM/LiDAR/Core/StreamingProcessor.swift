import Foundation
import SwiftUI
import ARKit

// MARK: - StreamingProcessor

class StreamingProcessor: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var isProcessing: Bool = false
    @Published var error: Error? = nil
    
    private var task: Task<Void, Never>?
    private var pointsProcessed: Int = 0
    private var totalPoints: Int = 0
    
    func startProcessing(points: [Point], chunkSize: Int) {
        guard !isProcessing else { return }
        
        isProcessing = true
        pointsProcessed = 0
        totalPoints = points.count
        error = nil
        
        task = Task {
            do {
                for chunk in stride(from: 0, to: points.count, by: chunkSize) {
                    let end = min(chunk + chunkSize, points.count)
                    let chunkPoints = Array(points[chunk..<end])
                    try await processChunk(chunkPoints)
                    updateProgress()
                }
                isProcessing = false
            } catch {
                self.error = error
                isProcessing = false
            }
        }
    }
    
    func stopProcessing() {
        task?.cancel()
        task = nil
        isProcessing = false
    }
    
    private func processChunk(_ points: [Point]) async throws {
        // Simulate processing time
        try await Task.sleep(nanoseconds: UInt64.random(in: 100_000_000...500_000_000))
        pointsProcessed += points.count
    }
    
    private func updateProgress() {
        progress = Double(pointsProcessed) / Double(totalPoints)
    }
}

// MARK: - Point

struct Point {
    let x: Double
    let y: Double
    let z: Double
}

// MARK: - StreamingProcessorView

struct StreamingProcessorView: View {
    @StateObject private var processor = StreamingProcessor()
    @State private var points: [Point] = []
    @State private var chunkSize: Int = 100
    
    var body: some View {
        VStack {
            Button("Start Processing") {
                processor.startProcessing(points: points, chunkSize: chunkSize)
            }
            .disabled(processor.isProcessing)
            
            Button("Stop Processing") {
                processor.stopProcessing()
            }
            .disabled(!processor.isProcessing)
            
            ProgressView(value: processor.progress)
                .padding()
            
            if let error = processor.error {
                Text("Error: \(error.localizedDescription)")
                    .foregroundColor(.red)
            }
        }
        .padding()
    }
}

// MARK: - Preview

struct StreamingProcessorView_Previews: PreviewProvider {
    static var previews: some View {
        StreamingProcessorView()
    }
}