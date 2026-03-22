import SwiftUI

struct EnvironmentMonitorView: View {
    @State private var sensor = EnvironmentSensor()

    var body: some View {
        NavigationStack {
            List {
                // Live readouts
                Section("Live Sensors") {
                    SensorRow(icon: "barometer", label: "Pressure",
                              value: String(format: "%.1f hPa", sensor.currentPressure),
                              color: .blue)
                    SensorRow(icon: "arrow.up.and.down", label: "Relative Altitude",
                              value: String(format: "%.1f m", sensor.currentAltitude),
                              color: .teal)
                    SensorRow(icon: "waveform.path.ecg", label: "Vibration (RMS)",
                              value: String(format: "%.3f g", sensor.currentAccel),
                              color: sensor.currentAccel > 0.15 ? .red : .green)
                    SensorRow(icon: "compass.drawing", label: "Heading",
                              value: String(format: "%.0f°", sensor.currentHeading),
                              color: .orange)
                }

                // Events
                Section("Anomaly Events (\(sensor.recentEvents.count))") {
                    if sensor.recentEvents.isEmpty {
                        Text("No anomalies detected")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(sensor.recentEvents) { event in
                            EventRow(event: event)
                        }
                    }
                }
            }
            .navigationTitle("Environment")
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(action: toggleMonitoring) {
                        Label(sensor.isMonitoring ? "Stop Monitor" : "Start Monitor",
                              systemImage: sensor.isMonitoring ? "stop.circle.fill" : "sensor.tag.radiowaves.forward")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(sensor.isMonitoring ? .red : .accentColor)

                    Spacer()

                    if !sensor.recentEvents.isEmpty,
                       let data = try? JSONEncoder().encode(sensor.recentEvents),
                       let str = String(data: data, encoding: .utf8) {
                        ShareLink(item: str, preview: .init("Environment Log")) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .overlay(alignment: .top) {
                if sensor.isMonitoring {
                    HStack(spacing: 6) {
                        Circle().fill(.red).frame(width: 8, height: 8)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: sensor.isMonitoring)
                        Text("Monitoring active")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                }
            }
        }
    }

    private func toggleMonitoring() {
        if sensor.isMonitoring { sensor.stopMonitoring() } else { sensor.startMonitoring() }
    }
}

struct SensorRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 28)
            Text(label)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

struct EventRow: View {
    let event: EnvironmentEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.type.icon)
                .foregroundStyle(eventColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.type.rawValue)
                    .font(.caption.bold())
                Text(String(format: "%.3f %@", event.value, event.unit))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(event.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .listRowBackground(eventColor.opacity(0.08))
    }

    var eventColor: Color {
        switch event.type {
        case .pressureDrop: return .blue
        case .vibrationSpike: return .red
        case .orientationChange: return .orange
        case .magneticAnomaly: return .purple
        }
    }
}
