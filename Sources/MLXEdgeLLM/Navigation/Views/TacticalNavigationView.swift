// TacticalNavigationView.swift — Navigation control UI (Boeing modular pattern)

import SwiftUI
import MapKit

/// Tactical navigation control view
struct TacticalNavigationView: View {
    @StateObject private var navStack = TacticalNavigationStack.shared
    @State private var destinationInput: String = ""
    @State private var showDestinationPicker = false

    var body: some View {
        ZStack {
            ZDDesign.darkBackground.ignoresSafeArea()

            VStack(spacing: 16) {
                // Status indicator
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Navigation")
                            .font(.headline)
                            .foregroundColor(ZDDesign.pureWhite)

                        switch navStack.status {
                        case .idle:
                            Text("Ready")
                                .font(.caption)
                                .foregroundColor(ZDDesign.mediumGray)
                        case .planning:
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Planning path...")
                                    .font(.caption)
                                    .foregroundColor(ZDDesign.cyanAccent)
                            }
                        case .executing(let current, let total, let remaining):
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Executing: \(current + 1)/\(total)")
                                    .font(.caption)
                                    .foregroundColor(ZDDesign.successGreen)
                                Text("\(Int(remaining))m remaining")
                                    .font(.caption2)
                                    .foregroundColor(ZDDesign.mediumGray)
                            }
                        case .completed:
                            Text("✓ Destination reached")
                                .font(.caption)
                                .foregroundColor(ZDDesign.successGreen)
                        case .error(let msg):
                            Text("Error: \(msg)")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                    Spacer()

                    // Celestial indicator
                    if navStack.currentCommand != nil {
                        VStack(alignment: .trailing, spacing: 2) {
                            Image(systemName: "sparkles")
                                .foregroundColor(ZDDesign.cyanAccent)
                            Text("Heading")
                                .font(.caption2)
                                .foregroundColor(ZDDesign.mediumGray)
                        }
                    }
                }
                .padding(12)
                .background(ZDDesign.darkCard)
                .cornerRadius(8)

                // Current command display
                if let cmd = navStack.currentCommand {
                    VStack(spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Speed: \(String(format: "%.1f", cmd.desiredSpeed)) m/s")
                                    .font(.caption)
                                    .foregroundColor(ZDDesign.pureWhite)
                                Text("Heading: \(Int(cmd.desiredHeading))°")
                                    .font(.caption)
                                    .foregroundColor(ZDDesign.pureWhite)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Turn: \(String(format: "%.1f", cmd.turnRate))°/s")
                                    .font(.caption)
                                    .foregroundColor(ZDDesign.cyanAccent)
                            }
                        }
                        .padding(8)
                        .background(ZDDesign.darkCard)
                        .cornerRadius(6)
                    }
                }

                Spacer()

                // Destination input
                VStack(spacing: 8) {
                    Text("Destination")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(ZDDesign.cyanAccent)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {
                        TextField("Coordinates or waypoint", text: $destinationInput)
                            .textFieldStyle(.roundedBorder)
                            .foregroundColor(ZDDesign.pureWhite)

                        Button(action: { showDestinationPicker = true }) {
                            Image(systemName: "location.fill")
                                .foregroundColor(ZDDesign.cyanAccent)
                        }
                    }
                }
                .padding(12)
                .background(ZDDesign.darkCard)
                .cornerRadius(8)

                // Control buttons
                HStack(spacing: 12) {
                    if case .executing = navStack.status {
                        Button(action: { navStack.stop() }) {
                            HStack {
                                Image(systemName: "stop.fill")
                                Text("Stop")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(.red.opacity(0.2))
                            .cornerRadius(6)
                            .foregroundColor(.red)
                        }
                    } else {
                        Button(action: {
                            let waypoint = NavWaypoint(
                                coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                                name: destinationInput.isEmpty ? nil : destinationInput
                            )
                            Task {
                                await navStack.start(destination: waypoint)
                            }
                        }) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Navigate")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(ZDDesign.successGreen)
                            .cornerRadius(6)
                            .foregroundColor(.black)
                        }
                        .disabled(destinationInput.isEmpty)
                    }
                }

                Spacer().frame(height: 8)
            }
            .padding()
        }
    }
}

#Preview {
    TacticalNavigationView()
}
