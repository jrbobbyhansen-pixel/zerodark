// CelestialNavSheet.swift — Celestial navigation status view (extracted from TeamMapView)

import SwiftUI

struct CelestialNavSheet: View {
    @StateObject private var celestial = CelestialNavigator()
    @Environment(\.dismiss) private var dismiss: DismissAction

    var body: some View {
        NavigationStack {
            ZStack {
                ZDDesign.darkBackground.ignoresSafeArea()

                VStack(spacing: 20) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(Color(ZDDesign.cyanAccent))

                    Text("Celestial Navigation")
                        .font(.title2)
                        .foregroundColor(Color(ZDDesign.pureWhite))

                    VStack(spacing: 8) {
                        HStack {
                            Circle()
                                .fill(celestial.isSessionRunning ? Color(ZDDesign.successGreen) : Color(ZDDesign.mediumGray))
                                .frame(width: 8, height: 8)
                            Text(celestial.isSessionRunning ? "Session Active" : "Session Inactive")
                                .foregroundColor(celestial.isSessionRunning ? Color(ZDDesign.successGreen) : Color(ZDDesign.mediumGray))
                        }

                        Text("Stars Detected: \(celestial.detectedStarCount)")
                            .font(.caption)
                            .foregroundColor(Color(ZDDesign.mediumGray))

                        if let heading = celestial.estimatedHeading {
                            Text("Heading: \(String(format: "%.1f°", heading))")
                                .font(.headline)
                                .foregroundColor(Color(ZDDesign.cyanAccent))
                        }
                    }

                    Text("Point camera at night sky to detect stars")
                        .foregroundColor(Color(ZDDesign.mediumGray))
                        .multilineTextAlignment(.center)
                        .font(.caption)

                    HStack(spacing: 16) {
                        Button(celestial.isSessionRunning ? "Stop" : "Start") {
                            if celestial.isSessionRunning {
                                celestial.stopSession()
                            } else {
                                celestial.startSession()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(celestial.isSessionRunning ? Color(ZDDesign.signalRed) : Color(ZDDesign.cyanAccent))
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Star Nav")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onDisappear {
            celestial.stopSession()
        }
    }
}
