import SwiftUI
import Combine

// MARK: - TimePressureManager

class TimePressureManager: ObservableObject {
    @Published var timeRemaining: TimeInterval = 0
    @Published var isRunning = false
    @Published var isPaused = false
    @Published var isFinished = false
    
    private var timer: Timer?
    private var startTime: Date?
    
    func startTimer(duration: TimeInterval) {
        guard !isRunning else { return }
        timeRemaining = duration
        isRunning = true
        isPaused = false
        isFinished = false
        startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateTimer()
        }
    }
    
    func pauseTimer() {
        guard isRunning && !isPaused else { return }
        isPaused = true
        timer?.invalidate()
    }
    
    func resumeTimer() {
        guard isRunning && isPaused else { return }
        isPaused = false
        startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateTimer()
        }
    }
    
    func stopTimer() {
        isRunning = false
        isPaused = false
        isFinished = true
        timer?.invalidate()
        timeRemaining = 0
    }
    
    private func updateTimer() {
        guard let startTime = startTime else { return }
        let elapsedTime = Date().timeIntervalSince(startTime)
        timeRemaining = max(0, timeRemaining - elapsedTime)
        if timeRemaining <= 0 {
            stopTimer()
        }
    }
}

// MARK: - TimePressureView

struct TimePressureView: View {
    @StateObject private var timePressureManager = TimePressureManager()
    
    var body: some View {
        VStack {
            Text("Time Remaining")
                .font(.headline)
            
            Text(timePressureManager.timeRemaining, specifier: "%.0f")
                .font(.largeTitle)
                .padding()
            
            HStack {
                Button(action: {
                    timePressureManager.startTimer(duration: 60) // 1 minute
                }) {
                    Text("Start")
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(timePressureManager.isRunning)
                
                Button(action: {
                    timePressureManager.pauseTimer()
                }) {
                    Text("Pause")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(!timePressureManager.isRunning || timePressureManager.isPaused)
                
                Button(action: {
                    timePressureManager.resumeTimer()
                }) {
                    Text("Resume")
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(!timePressureManager.isPaused)
                
                Button(action: {
                    timePressureManager.stopTimer()
                }) {
                    Text("Stop")
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(!timePressureManager.isRunning)
            }
        }
        .padding()
    }
}

// MARK: - Preview

struct TimePressureView_Previews: PreviewProvider {
    static var previews: some View {
        TimePressureView()
    }
}