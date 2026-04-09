// OpsTabView.swift — Unified Operations & Command Center (Deep Pack v7.0)
// 6-section nexus: Planner, Team, Eval, Reports, Sims, OpSec
// Persistent OpsCommsStrip for mesh/PTT/SOS/alerts

import SwiftUI

// MARK: - Ops Mode Enum

enum OpsMode: String, CaseIterable {
    case planner  = "Planner"
    case team     = "Team"
    case medical  = "Medical"
    case planning = "Planning"
    case eval     = "Eval"
    case reports  = "Reports"
    case sims     = "Sims"
    case opSec    = "OpSec"

    var icon: String {
        switch self {
        case .planner:  return "flag.fill"
        case .team:     return "person.3.fill"
        case .medical:  return "cross.fill"
        case .planning: return "list.bullet.clipboard"
        case .eval:     return "star.fill"
        case .reports:  return "doc.text.fill"
        case .sims:     return "antenna.radiowaves.left.and.right"
        case .opSec:    return "lock.shield.fill"
        }
    }
}

// MARK: - OpsTabView

struct OpsTabView: View {
    @StateObject private var mesh = MeshService.shared
    @StateObject private var activity = ActivityFeed.shared
    @State private var opsMode: OpsMode = .planner
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            ZStack {
                ZDDesign.darkBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Persistent comms strip
                    OpsCommsStrip()
                        .padding(.horizontal)
                        .padding(.top, 4)

                    // Mode picker
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(OpsMode.allCases, id: \.self) { mode in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        opsMode = mode
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: mode.icon)
                                            .font(.system(size: 10))
                                        Text(mode.rawValue)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(opsMode == mode ? ZDDesign.cyanAccent : ZDDesign.darkCard)
                                    .foregroundColor(opsMode == mode ? .black : ZDDesign.pureWhite)
                                    .cornerRadius(ZDDesign.radiusSmall)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }

                    // Section content
                    Group {
                        switch opsMode {
                        case .planner:
                            MissionPlannerSection()
                        case .team:
                            TeamDashSection()
                        case .medical:
                            MedicalSection()
                        case .planning:
                            PlanningToolsSection()
                        case .eval:
                            EvalDebriefSection()
                        case .reports:
                            ReportsSection()
                        case .sims:
                            SimsSection()
                        case .opSec:
                            OpSecSection()
                        }
                    }
                }
            }
            .navigationTitle("Operations")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New Incident", systemImage: "plus.circle") {
                            // Create incident
                        }
                        Button("Export Logs", systemImage: "square.and.arrow.up") {
                            exportURL = activity.exportLogs()
                        }
                        Divider()
                        if mesh.isActive {
                            Button("Leave Mesh", systemImage: "xmark.circle", role: .destructive) {
                                mesh.stop()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }
            .sheet(item: $exportURL) { url in
                ShareSheet(items: [url])
            }
        }
    }
}

#Preview {
    OpsTabView()
}
