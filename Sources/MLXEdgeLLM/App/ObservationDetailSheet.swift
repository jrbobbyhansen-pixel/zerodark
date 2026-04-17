// ObservationDetailSheet.swift — Detail view for a tapped field observation map pin

import SwiftUI
import CoreLocation

struct ObservationDetailSheet: View {
    let observation: FieldObservation
    let logger: ObservationLogger
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Header band — category color + icon
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(observation.category.mapColor)
                                .frame(width: 48, height: 48)
                            Image(systemName: observation.category.mapIcon)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.black)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(observation.category.rawValue.uppercased())
                                .font(.system(size: 13, weight: .black, design: .monospaced))
                                .foregroundColor(observation.category.mapColor)
                                .tracking(2)
                            Text(relativeTime(observation.timestamp))
                                .font(.caption)
                                .foregroundColor(ZDDesign.mediumGray)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(observation.category.mapColor.opacity(0.12))

                    Divider()

                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.caption)
                            .foregroundColor(ZDDesign.mediumGray)
                        Text(observation.description.isEmpty ? "No description" : observation.description)
                            .font(.body)
                            .foregroundColor(ZDDesign.pureWhite)
                            .textSelection(.enabled)
                    }
                    .padding()

                    Divider()

                    // Bearing + distance
                    HStack(spacing: 24) {
                        labeledValue("Bearing", value: String(format: "%.0f°", observation.bearing))
                        labeledValue("Distance", value: observation.distance > 0
                            ? String(format: "%.0f m", observation.distance)
                            : "N/A")
                        labeledValue("Time", value: observation.timestamp.formatted(date: .omitted, time: .shortened))
                    }
                    .padding()

                    Divider()

                    // GPS coordinates
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Location")
                            .font(.caption)
                            .foregroundColor(ZDDesign.mediumGray)
                        Text(String(format: "%.5f, %.5f", observation.latitude, observation.longitude))
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(ZDDesign.cyanAccent)
                            .textSelection(.enabled)
                    }
                    .padding()

                    Divider()

                    // Open in Maps
                    if observation.latitude != 0 || observation.longitude != 0 {
                        Button {
                            let coord = observation.coordinate
                            let item = MKMapItem(placemark: MKPlacemark(coordinate: coord))
                            item.name = "[\(observation.category.rawValue)] Observation"
                            item.openInMaps()
                        } label: {
                            Label("Open in Maps", systemImage: "map")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(ZDDesign.cyanAccent)
                        .padding()
                    }
                }
            }
            .background(ZDDesign.darkBackground)
            .navigationTitle("Observation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) {
                        if let idx = logger.observations.firstIndex(where: { $0.id == observation.id }) {
                            logger.observations.remove(at: idx)
                        }
                        dismiss()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(ZDDesign.signalRed)
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func labeledValue(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(ZDDesign.mediumGray)
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(ZDDesign.pureWhite)
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

// Make MKMapItem available for "Open in Maps"
import MapKit
