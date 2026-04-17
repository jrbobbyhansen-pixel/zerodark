// TeamDashSection.swift — Ops > Team sub-section
// Composes: Team status, weather/conditions, safety monitor, check-in

import SwiftUI

struct TeamDashSection: View {
    @ObservedObject private var mesh = MeshService.shared
    @ObservedObject private var weather = WeatherService.shared
    @ObservedObject private var safetyMonitor = RuntimeSafetyMonitor.shared
    @ObservedObject private var teamPack = TeamPackStore.shared
    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            VStack(spacing: ZDDesign.spacing16) {
                // Live Team Status
                teamStatusCard

                // Conditions (Weather)
                conditionsCard

                // Team Management Tools
                OpsSectionHeader(icon: "person.3.fill", title: "TEAM MANAGEMENT", color: ZDDesign.cyanAccent)

                NavigationLink {
                    TeamRosterView()
                } label: {
                    OpsSectionCard(
                        icon: "person.2.wave.2.fill",
                        title: "Team Roster",
                        subtitle: "Manage members, callsigns, roles & medical data",
                        color: ZDDesign.cyanAccent
                    )
                }

                NavigationLink {
                    CheckInView()
                } label: {
                    OpsSectionCard(
                        icon: "checkmark.shield.fill",
                        title: "Check-In System",
                        subtitle: "Scheduled mesh check-ins, overdue alerts, escalation",
                        color: .green
                    )
                }

                NavigationLink {
                    StatusBoardView()
                } label: {
                    OpsSectionCard(
                        icon: "chart.bar.xaxis",
                        title: "Status Board",
                        subtitle: "Live team grid: location, battery, status, overdue overlay",
                        color: ZDDesign.safetyYellow
                    )
                }

                NavigationLink {
                    RallyPointView()
                } label: {
                    OpsSectionCard(
                        icon: "mappin.and.ellipse",
                        title: "Rally Points",
                        subtitle: "Primary & alternate RPs, mesh broadcast, peer ETAs",
                        color: .orange
                    )
                }

                NavigationLink {
                    SearchPatternView()
                } label: {
                    OpsSectionCard(
                        icon: "magnifyingglass",
                        title: "Search Patterns",
                        subtitle: "SAR parallel track, expanding square, sector, contour; sector assignment & coverage",
                        color: .purple
                    )
                }

                NavigationLink {
                    TaskAssignmentView()
                } label: {
                    OpsSectionCard(
                        icon: "checklist",
                        title: "Task Assignment",
                        subtitle: "Create, assign, prioritize tasks; mesh push notifications; overdue alerts",
                        color: .blue
                    )
                }

                NavigationLink {
                    IncidentLogView()
                } label: {
                    OpsSectionCard(
                        icon: "doc.text.magnifyingglass",
                        title: "Incident Log",
                        subtitle: "Timestamped incidents, auto-GPS, photo/category; CSV/JSON export",
                        color: .red
                    )
                }

                NavigationLink {
                    ResourceTrackerView()
                } label: {
                    OpsSectionCard(
                        icon: "bag.fill",
                        title: "Resource Tracker",
                        subtitle: "Water, food, batteries, medical, ammo — consumption log & resupply planner",
                        color: .green
                    )
                }

                // Safety Monitor
                safetyMonitorCard
            }
            .padding(.horizontal)
        }
        .sheet(isPresented: $showPaywall) {
            TeamPackPaywall()
        }
    }

    // MARK: - Team Status Card

    private var teamStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            OpsSectionHeader(icon: "person.2.fill", title: "TEAM STATUS", color: ZDDesign.cyanAccent)

            TeamMemberRow(
                name: "You",
                status: .online,
                batteryLevel: getBatteryLevel(),
                isYou: true
            )

            if mesh.peers.isEmpty {
                Text("No other team members connected")
                    .font(.caption)
                    .foregroundColor(ZDDesign.mediumGray)
                    .padding(.vertical, 8)
            } else {
                let visiblePeers = teamPack.hasUnlimitedRoster
                    ? mesh.peers
                    : Array(mesh.peers.prefix(TeamPackStore.freeRosterLimit))

                ForEach(visiblePeers) { peer in
                    TeamMemberRow(
                        name: peer.name,
                        status: peer.status,
                        batteryLevel: peer.batteryLevel,
                        lastSeen: peer.lastSeen
                    )
                }

                if !teamPack.hasUnlimitedRoster && mesh.peers.count > TeamPackStore.freeRosterLimit {
                    Button {
                        showPaywall = true
                    } label: {
                        HStack {
                            Image(systemName: "lock.fill")
                            Text("+\(mesh.peers.count - TeamPackStore.freeRosterLimit) more — Unlock TeamPack")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(ZDDesign.cyanAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(ZDDesign.cyanAccent.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(ZDDesign.radiusMedium)
    }

    // MARK: - Conditions Card

    private var conditionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            OpsSectionHeader(icon: "cloud.sun.fill", title: "CONDITIONS", color: ZDDesign.safetyYellow)

            if let conditions = weather.currentConditions {
                HStack(spacing: 20) {
                    VStack {
                        Text("\(conditions.temperature)\u{00B0}F")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(ZDDesign.pureWhite)
                        Text(conditions.description)
                            .font(.caption)
                            .foregroundColor(ZDDesign.mediumGray)
                    }

                    Divider().frame(height: 40).background(ZDDesign.mediumGray)

                    VStack {
                        HStack(spacing: 4) {
                            Image(systemName: "wind")
                                .foregroundColor(ZDDesign.cyanAccent)
                            Text("\(conditions.windSpeed) mph")
                                .foregroundColor(ZDDesign.pureWhite)
                        }
                        Text(conditions.windDirection)
                            .font(.caption)
                            .foregroundColor(ZDDesign.mediumGray)
                    }

                    Divider().frame(height: 40).background(ZDDesign.mediumGray)

                    VStack {
                        HStack(spacing: 4) {
                            Image(systemName: "sunset.fill")
                                .foregroundColor(.orange)
                            Text(conditions.sunset.formatted(date: .omitted, time: .shortened))
                                .foregroundColor(ZDDesign.pureWhite)
                        }
                        Text("Sunset")
                            .font(.caption)
                            .foregroundColor(ZDDesign.mediumGray)
                    }
                }
            } else {
                HStack {
                    ProgressView().tint(ZDDesign.cyanAccent)
                    Text("Loading conditions...")
                        .foregroundColor(ZDDesign.mediumGray)
                }
                .onAppear { weather.fetchConditions() }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(ZDDesign.radiusMedium)
    }

    // MARK: - Safety Monitor Card

    private var safetyMonitorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                OpsSectionHeader(icon: "checkmark.shield.fill", title: "SAFETY STATUS")
                Spacer()
                Circle()
                    .fill(safetyMonitor.unresolvedViolations.isEmpty ? ZDDesign.successGreen : ZDDesign.signalRed)
                    .frame(width: 8, height: 8)
            }

            if safetyMonitor.unresolvedViolations.isEmpty {
                HStack {
                    Image(systemName: "checkmark.shield.fill").foregroundColor(ZDDesign.successGreen)
                    Text("All systems nominal").foregroundColor(ZDDesign.mediumGray).font(.subheadline)
                }
            } else {
                ForEach(safetyMonitor.unresolvedViolations.prefix(3)) { violation in
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(violation.severity >= 2 ? ZDDesign.signalRed : ZDDesign.safetyYellow)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(violation.property).font(.subheadline).foregroundColor(ZDDesign.pureWhite)
                            Text(violation.details).font(.caption).foregroundColor(ZDDesign.mediumGray)
                        }
                    }
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(ZDDesign.radiusMedium)
    }

    // MARK: - Helpers

    private func getBatteryLevel() -> Int {
        #if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true
        return Int(UIDevice.current.batteryLevel * 100)
        #else
        return 100
        #endif
    }
}
