// TelemetryDashboard.swift — MCT-style composable telemetry panel grid

import SwiftUI

/// Wrapper for selected panel
struct SelectedPanel: Identifiable {
    let id = UUID()
    let type: TelemetryObjectType
}

/// Main telemetry dashboard
struct TelemetryDashboard: View {
    @StateObject private var store = TelemetryStore.shared
    @State private var selectedPanel: SelectedPanel? = nil

    var body: some View {
        ZStack {
            ZDDesign.darkBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    Text("Telemetry Dashboard")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(ZDDesign.pureWhite)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

            // Panel grid (2 columns)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(TelemetryObjectType.allCases, id: \.self) { type in
                            if let obj = store.object(for: type) {
                                TelemetryPanel(object: obj)
                                    .onTapGesture {
                                        selectedPanel = SelectedPanel(type: type)
                                    }
                            }
                        }
                    }
                    .padding(.horizontal)

                    Spacer().frame(height: 20)
                }
                .padding(.vertical)
            }

            // Detail sheet
            if let panel = selectedPanel, let obj = store.object(for: panel.type) {
                TelemetryDetailView(object: obj, isPresented: $selectedPanel)
            }
        }
    }
}

/// Single telemetry panel
struct TelemetryPanel: View {
    let object: TelemetryObject

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: object.type.icon)
                    .font(.title3)
                    .foregroundColor(ZDDesign.cyanAccent)

                Text(object.type.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(ZDDesign.pureWhite)

                Spacer()

                // Update indicator
                if let latest = object.latestValue {
                    updateBadge(for: latest)
                }
            }

            // Latest value display
            if let latest = object.latestValue {
                valueDisplay(for: latest)
                    .font(.headline)
                    .foregroundColor(ZDDesign.cyanAccent)
            }

            // Mini chart placeholder
            if object.data.count > 1 {
                ZStack {
                    ZDDesign.darkBackground.opacity(0.5)
                    Text("\(object.data.count) readings")
                        .font(.caption2)
                        .foregroundColor(ZDDesign.mediumGray)
                }
                .frame(height: 30)
                .cornerRadius(4)
            }

            Text("Updated: \(formatTime(object.updatedAt))")
                .font(.caption2)
                .foregroundColor(ZDDesign.mediumGray)
        }
        .padding(12)
        .background(ZDDesign.darkCard)
        .cornerRadius(8)
    }

    private func valueDisplay(for value: TelemetryValue) -> some View {
        switch value {
        case .double(let d):
            return AnyView(Text(String(format: "%.2f", d)))
        case .int(let i):
            return AnyView(Text("\(i)"))
        case .string(let s):
            return AnyView(Text(s).lineLimit(1))
        case .bool(let b):
            return AnyView(Text(b ? "Active" : "Inactive"))
        }
    }

    private func updateBadge(for value: TelemetryValue) -> some View {
        Circle()
            .fill(ZDDesign.successGreen)
            .frame(width: 8, height: 8)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

/// Detail view for selected panel
struct TelemetryDetailView: View {
    @StateObject private var store = TelemetryStore.shared
    let object: TelemetryObject
    @Binding var isPresented: SelectedPanel?

    var body: some View {
        ZStack {
            ZDDesign.darkBackground.ignoresSafeArea()

            VStack(spacing: 16) {
                // Header
                HStack {
                    Button(action: { isPresented = nil }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(ZDDesign.cyanAccent)
                    }

                    Spacer()

                    Text(object.type.displayName)
                        .font(.headline)
                        .foregroundColor(ZDDesign.pureWhite)

                    Spacer()

                    Image(systemName: object.type.icon)
                        .foregroundColor(ZDDesign.cyanAccent)
                }
                .padding()

                // Timeline chart
                TelemetryTimelineChart(object: object)
                    .frame(height: 200)
                    .padding()

                // Data table
                List {
                    ForEach(Array(object.data.reversed().enumerated()), id: \.offset) { _, datum in
                        HStack {
                            Text(formatTime(datum.timestamp))
                                .font(.caption)
                                .foregroundColor(ZDDesign.mediumGray)

                            Spacer()

                            valueDisplay(for: datum.value)
                                .font(.caption)
                                .foregroundColor(ZDDesign.cyanAccent)
                        }
                        .listRowBackground(ZDDesign.darkCard)
                    }
                }
                .listStyle(.plain)

                Spacer()
            }
        }
    }

    private func valueDisplay(for value: TelemetryValue) -> some View {
        switch value {
        case .double(let d):
            return AnyView(Text(String(format: "%.2f", d)))
        case .int(let i):
            return AnyView(Text("\(i)"))
        case .string(let s):
            return AnyView(Text(s).lineLimit(1))
        case .bool(let b):
            return AnyView(Text(b ? "Active" : "Inactive"))
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

/// Timeline chart for telemetry data
struct TelemetryTimelineChart: View {
    let object: TelemetryObject

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(ZDDesign.cyanAccent)
                Text("\(object.data.count) data points")
                    .font(.caption)
                    .foregroundColor(ZDDesign.mediumGray)
                Spacer()
            }
            .padding(.bottom, 8)

            ZStack {
                ZDDesign.darkCard
                VStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        HStack {
                            Capsule()
                                .fill(ZDDesign.cyanAccent.opacity(0.3 + CGFloat(i) * 0.2))
                                .frame(width: CGFloat(50 + i * 30), height: 4)
                            Spacer()
                        }
                    }
                }
                .padding(12)
            }
        }
        .padding(0)
        .background(ZDDesign.darkCard)
        .cornerRadius(8)
    }
}
