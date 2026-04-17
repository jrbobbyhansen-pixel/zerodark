// ScanSummarySheet.swift — Detail view for a tapped LiDAR scan map pin

import SwiftUI

struct ScanSummarySheet: View {
    let sceneTag: SceneTag
    let store: SceneTagStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Risk score bar
                    riskBar

                    Divider()

                    // Scan metadata
                    HStack(spacing: 24) {
                        labeledValue("Date", value: sceneTag.timestamp.formatted(date: .abbreviated, time: .omitted))
                        labeledValue("Time", value: sceneTag.timestamp.formatted(date: .omitted, time: .shortened))
                        labeledValue("Points", value: sceneTag.pointCount.formatted())
                    }
                    .padding()

                    Divider()

                    // Threat + cover summary
                    HStack(spacing: 24) {
                        labeledValue("Threats", value: "\(sceneTag.threats.count)", accent: sceneTag.threats.isEmpty ? .secondary : Color(ZDDesign.signalRed))
                        labeledValue("Cover Positions", value: "\(sceneTag.covers.count)", accent: Color(ZDDesign.successGreen))
                    }
                    .padding()

                    if !sceneTag.threats.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Detected Threats")
                                .font(.caption)
                                .foregroundColor(ZDDesign.mediumGray)
                            ForEach(sceneTag.threats.prefix(5)) { threat in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(ZDDesign.signalRed).opacity(0.8))
                                        .frame(width: 6, height: 6)
                                    Text(threat.className)
                                        .font(.caption)
                                        .foregroundColor(ZDDesign.pureWhite)
                                    Spacer()
                                    Text(String(format: "%.0f%%", threat.confidence * 100))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundColor(ZDDesign.mediumGray)
                                    if let dist = threat.distance {
                                        Text(String(format: "%.1fm", dist))
                                            .font(.caption2.monospacedDigit())
                                            .foregroundColor(ZDDesign.mediumGray)
                                    }
                                }
                            }
                        }
                        .padding()
                    }

                    if let assessment = sceneTag.assessment, !assessment.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tactical Assessment")
                                .font(.caption)
                                .foregroundColor(ZDDesign.mediumGray)
                            Text(assessment)
                                .font(.body)
                                .lineSpacing(4)
                                .foregroundColor(ZDDesign.pureWhite)
                                .textSelection(.enabled)
                        }
                        .padding()
                    }

                    if let loc = sceneTag.location {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Location")
                                .font(.caption)
                                .foregroundColor(ZDDesign.mediumGray)
                            Text(String(format: "%.5f, %.5f", loc.latitude, loc.longitude))
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(ZDDesign.cyanAccent)
                                .textSelection(.enabled)
                        }
                        .padding()
                    }

                    Divider()

                    // View Full Report
                    NavigationLink {
                        ScanGalleryView()
                    } label: {
                        Label("View Full Report", systemImage: "doc.text.magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(ZDDesign.cyanAccent)
                    .padding()
                }
            }
            .background(ZDDesign.darkBackground)
            .navigationTitle("LiDAR Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) {
                        store.delete(id: sceneTag.id)
                        dismiss()
                    } label: {
                        Image(systemName: "mappin.slash")
                            .foregroundColor(ZDDesign.signalRed)
                    }
                    .help("Remove pin from map")
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Risk bar

    private var riskBar: some View {
        let risk = sceneTag.riskScore ?? 0
        let color = lidarRiskColor(risk)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(riskLabel(risk))
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundColor(color)
                    .tracking(1)
                Spacer()
                Text(String(format: "%.0f%%", risk * 100))
                    .font(.system(size: 22, weight: .black, design: .monospaced))
                    .foregroundColor(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(ZDDesign.warmGray.opacity(0.3))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [Color(ZDDesign.successGreen), Color(ZDDesign.safetyYellow), Color(ZDDesign.warningOrange), Color(ZDDesign.signalRed)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(risk), height: 8)
                        .animation(.easeOut(duration: 0.4), value: risk)
                }
            }
            .frame(height: 8)
        }
        .padding()
    }

    // MARK: - Helpers

    private func labeledValue(_ label: String, value: String, accent: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(ZDDesign.mediumGray)
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(accent ?? ZDDesign.pureWhite)
        }
    }

    private func riskLabel(_ risk: Float) -> String {
        switch risk {
        case ..<0.3:  return "LOW RISK"
        case ..<0.6:  return "MODERATE RISK"
        case ..<0.8:  return "HIGH RISK"
        default:      return "CRITICAL RISK"
        }
    }

    private func lidarRiskColor(_ risk: Float) -> Color {
        switch risk {
        case ..<0.3:  return Color(ZDDesign.successGreen)
        case ..<0.6:  return Color(ZDDesign.safetyYellow)
        case ..<0.8:  return Color(ZDDesign.warningOrange)
        default:      return Color(ZDDesign.signalRed)
        }
    }
}
