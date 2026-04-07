import Foundation
import SwiftUI
import AVFoundation

class TourniquetTimer: ObservableObject {
    @Published var tourniquets: [Tourniquet] = []
    private let alertSound = URL(fileURLWithPath: Bundle.main.path(forResource: "alert", ofType: "mp3")!)
    private let audioPlayer = try! AVAudioPlayer(contentsOf: alertSound)
    
    func startTourniquet(for limb: Limb, duration: TimeInterval) {
        let tourniquet = Tourniquet(limb: limb, duration: duration)
        tourniquets.append(tourniquet)
        tourniquet.start()
    }
    
    func stopTourniquet(for limb: Limb) {
        if let index = tourniquets.firstIndex(where: { $0.limb == limb }) {
            tourniquets[index].stop()
            tourniquets.remove(at: index)
        }
    }
}

class Tourniquet: ObservableObject {
    @Published var timeRemaining: TimeInterval
    let limb: Limb
    private var timer: Timer?
    
    init(limb: Limb, duration: TimeInterval) {
        self.limb = limb
        self.timeRemaining = duration
    }
    
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.timeRemaining -= 1
            if self.timeRemaining <= 0 {
                self.stop()
            } else if self.timeRemaining % 10 == 0 {
                self.playAlertSound()
            }
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    private func playAlertSound() {
        audioPlayer.currentTime = 0
        audioPlayer.play()
    }
}

enum Limb: String, CaseIterable {
    case leftArm
    case rightArm
    case leftLeg
    case rightLeg
}

struct TourniquetTimerView: View {
    @StateObject private var tourniquetTimer = TourniquetTimer()
    
    var body: some View {
        VStack {
            ForEach(TourniquetTimer.Limb.allCases, id: \.self) { limb in
                HStack {
                    Text(limb.rawValue)
                    Spacer()
                    Button(action: {
                        tourniquetTimer.startTourniquet(for: limb, duration: 600) // 10 minutes
                    }) {
                        Text("Start")
                    }
                    Button(action: {
                        tourniquetTimer.stopTourniquet(for: limb)
                    }) {
                        Text("Stop")
                    }
                }
            }
        }
        .padding()
    }
}

struct TourniquetTimer_Previews: PreviewProvider {
    static var previews: some View {
        TourniquetTimerView()
    }
}