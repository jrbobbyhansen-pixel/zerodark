import SwiftUI
import CoreLocation

// MARK: - DarkModeSystem

class DarkModeSystem: ObservableObject {
    @Published var isDarkModeEnabled: Bool = false
    @Published var isRedModeEnabled: Bool = false
    @Published var autoSwitchEnabled: Bool = true
    
    private let locationManager = CLLocationManager()
    
    init() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startMonitoringSignificantLocationChanges()
        
        // Initial mode setup
        updateModeBasedOnTime()
    }
    
    func toggleDarkMode() {
        isDarkModeEnabled.toggle()
    }
    
    func toggleRedMode() {
        isRedModeEnabled.toggle()
    }
    
    func toggleAutoSwitch() {
        autoSwitchEnabled.toggle()
        if autoSwitchEnabled {
            updateModeBasedOnTime()
        }
    }
    
    private func updateModeBasedOnTime() {
        let hour = Calendar.current.component(.hour, from: Date())
        isDarkModeEnabled = hour >= 20 || hour < 6
    }
}

// MARK: - CLLocationManagerDelegate

extension DarkModeSystem: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if autoSwitchEnabled {
            updateModeBasedOnTime()
        }
    }
}

// MARK: - DarkModeViewModifier

struct DarkModeViewModifier: ViewModifier {
    @ObservedObject var darkModeSystem: DarkModeSystem
    
    func body(content: Content) -> some View {
        content
            .environment(\.colorScheme, darkModeSystem.isDarkModeEnabled ? .dark : .light)
            .overlay(
                Group {
                    if darkModeSystem.isRedModeEnabled {
                        Color.red.opacity(0.5)
                            .edgesIgnoringSafeArea(.all)
                    }
                }
            )
    }
}

// MARK: - DarkModeEnvironmentKey

struct DarkModeEnvironmentKey: EnvironmentKey {
    static let defaultValue: DarkModeSystem = DarkModeSystem()
}

extension EnvironmentValues {
    var darkModeSystem: DarkModeSystem {
        get { self[DarkModeEnvironmentKey.self] }
        set { self[DarkModeEnvironmentKey.self] = newValue }
    }
}

// MARK: - DarkModePreferenceKey

struct DarkModePreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false
    
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

// MARK: - DarkModeView

struct DarkModeView: View {
    @StateObject private var darkModeSystem = DarkModeSystem()
    
    var body: some View {
        VStack {
            Toggle("Dark Mode", isOn: $darkModeSystem.isDarkModeEnabled)
            Toggle("Red Mode", isOn: $darkModeSystem.isRedModeEnabled)
            Toggle("Auto Switch", isOn: $darkModeSystem.autoSwitchEnabled)
        }
        .padding()
        .modifier(DarkModeViewModifier(darkModeSystem: darkModeSystem))
        .environmentObject(darkModeSystem)
    }
}

// MARK: - Preview

struct DarkModeView_Previews: PreviewProvider {
    static var previews: some View {
        DarkModeView()
    }
}