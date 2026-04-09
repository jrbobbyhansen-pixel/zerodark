// MeasurementOverlayView.swift — Measurement UI overlay for scan viewer

import SwiftUI

struct MeasurementOverlayView: View {
    @ObservedObject var manager: MeasurementManager
    @State private var showMeasurementList = false

    var body: some View {
        VStack {
            // Top toolbar
            HStack {
                // Measurement type picker
                if manager.isActive {
                    Picker("Type", selection: $manager.currentType) {
                        ForEach(MeasurementType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 250)
                    .onChange(of: manager.currentType) { _, _ in
                        manager.currentPoints = []
                    }
                }

                Spacer()

                // Unit toggle
                Button {
                    manager.unit = manager.unit == .metric ? .imperial : .metric
                } label: {
                    Text(manager.unit == .metric ? "m" : "ft")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(ZDDesign.pureWhite.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Spacer()

            // Live measurement display
            if manager.isActive {
                VStack(spacing: 8) {
                    // Instruction
                    Text(manager.instructionText)
                        .font(.caption)
                        .foregroundColor(ZDDesign.pureWhite)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(ZDDesign.darkBackground.opacity(0.7))
                        .cornerRadius(8)

                    // Current value (if measuring)
                    if let value = manager.currentMeasurementValue {
                        Text(value)
                            .font(.title2.bold().monospacedDigit())
                            .foregroundColor(ZDDesign.cyanAccent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(ZDDesign.darkBackground.opacity(0.8))
                            .cornerRadius(8)
                    }

                    // Point indicators
                    HStack(spacing: 4) {
                        ForEach(0..<max(manager.pointsNeeded, manager.currentPoints.count), id: \.self) { i in
                            Circle()
                                .fill(i < manager.currentPoints.count ? ZDDesign.cyanAccent : Color.gray.opacity(0.5))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }

            // Bottom toolbar
            HStack(spacing: 16) {
                // Measurements list button
                Button {
                    showMeasurementList = true
                } label: {
                    HStack {
                        Image(systemName: "list.bullet")
                        if !manager.annotations.measurements.isEmpty {
                            Text("\(manager.annotations.measurements.count)")
                                .font(.caption.bold())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(ZDDesign.pureWhite.opacity(0.15))
                    .cornerRadius(8)
                }

                Spacer()

                if manager.isActive {
                    // Cancel button
                    Button {
                        manager.cancelMeasurement()
                    } label: {
                        Text("Cancel")
                            .foregroundColor(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(ZDDesign.pureWhite.opacity(0.15))
                            .cornerRadius(8)
                    }

                    // Done button (for area)
                    if manager.currentType == .area && manager.canComplete {
                        Button {
                            manager.completeMeasurement()
                        } label: {
                            Text("Done")
                                .foregroundColor(ZDDesign.cyanAccent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(ZDDesign.pureWhite.opacity(0.15))
                                .cornerRadius(8)
                        }
                    }
                } else {
                    // Start measurement button
                    Button {
                        manager.startMeasurement(type: .distance)
                    } label: {
                        HStack {
                            Image(systemName: "ruler")
                            Text("Measure")
                        }
                        .foregroundColor(ZDDesign.pureWhite)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(ZDDesign.cyanAccent)
                        .cornerRadius(8)
                    }
                }
            }
            .padding()
        }
        .sheet(isPresented: $showMeasurementList) {
            MeasurementListView(manager: manager)
        }
    }
}

// MARK: - Measurement List

struct MeasurementListView: View {
    @ObservedObject var manager: MeasurementManager
    @Environment(\.dismiss) var dismiss: DismissAction

    var body: some View {
        NavigationStack {
            Group {
                if manager.annotations.measurements.isEmpty {
                    VStack {
                        Image(systemName: "ruler")
                            .font(.largeTitle)
                            .foregroundColor(ZDDesign.mediumGray)
                        Text("No measurements")
                            .foregroundColor(ZDDesign.mediumGray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(manager.annotations.measurements) { measurement in
                            MeasurementRow(measurement: measurement, unit: manager.unit)
                        }
                        .onDelete { indexSet in
                            let toDelete = indexSet.map { manager.annotations.measurements[$0] }
                            toDelete.forEach { manager.deleteMeasurement($0) }
                        }
                    }
                }
            }
            .navigationTitle("Measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !manager.annotations.measurements.isEmpty {
                        Button("Clear All", role: .destructive) {
                            manager.deleteAllMeasurements()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct MeasurementRow: View {
    let measurement: MeasurementAnnotation
    let unit: MeasurementUnit

    var body: some View {
        HStack {
            Image(systemName: measurement.type.icon)
                .foregroundColor(ZDDesign.cyanAccent)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(measurement.label ?? measurement.type.rawValue)
                    .font(.headline)
                Text(measurement.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(ZDDesign.mediumGray)
            }

            Spacer()

            Text(measurement.displayValue(unit: unit))
                .font(.headline.monospacedDigit())
                .foregroundColor(ZDDesign.cyanAccent)
        }
        .padding(.vertical, 4)
    }
}
