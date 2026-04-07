import SwiftUI
import Foundation

// MARK: - Accessibility Suite

struct AccessibilitySuite {
    // MARK: - VoiceOver
    static func announce(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }
    
    // MARK: - Dynamic Type
    static func dynamicTypeSize() -> DynamicTypeSize {
        return DynamicTypeSize(.large)
    }
    
    // MARK: - Reduce Motion
    static func isReduceMotionEnabled() -> Bool {
        return UIAccessibility.isReduceMotionEnabled
    }
    
    // MARK: - High Contrast Mode
    static func isHighContrastEnabled() -> Bool {
        return UIAccessibility.isHighContrastEnabled
    }
    
    // MARK: - Haptic Feedback
    static func generateHapticFeedback() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

// MARK: - SwiftUI Extensions

extension View {
    func announceOnAppear(_ message: String) -> some View {
        onAppear {
            AccessibilitySuite.announce(message)
        }
    }
    
    func dynamicTypeSupport() -> some View {
        accessibility(label: Text("Dynamic Type Support"))
    }
    
    func reduceMotionSupport() -> some View {
        accessibility(label: Text("Reduce Motion Support"))
    }
    
    func highContrastSupport() -> some View {
        accessibility(label: Text("High Contrast Support"))
    }
    
    func hapticFeedbackOnTap() -> some View {
        onTapGesture {
            AccessibilitySuite.generateHapticFeedback()
        }
    }
}

// MARK: - Example Usage

struct AccessibilityExampleView: View {
    var body: some View {
        VStack {
            Text("Welcome to ZeroDark")
                .font(.largeTitle)
                .announceOnAppear("Welcome to ZeroDark")
                .dynamicTypeSupport()
                .reduceMotionSupport()
                .highContrastSupport()
            
            Button("Generate Haptic Feedback") {
                AccessibilitySuite.generateHapticFeedback()
            }
            .hapticFeedbackOnTap()
        }
        .padding()
    }
}

struct AccessibilityExampleView_Previews: PreviewProvider {
    static var previews: some View {
        AccessibilityExampleView()
    }
}