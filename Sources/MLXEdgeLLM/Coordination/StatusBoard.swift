// StatusBoard.swift — Real-time team status grid from MeshService peers
// Displays all connected peers: location, last update, battery, status badge.
// Overlays check-in overdue warnings. Sort by distance or status.

import SwiftUI
import CoreLocation

// MARK: - Board Entry (combines ZDPeer + CheckIn overdue)

struct BoardEntry: Identifiable {
    let id: String   // peer.id
    let name: String
    let location: CLLocationCoordinate2D?
    let lastSeen: Date
    let batteryLevel: Int?
    let peerStatus: ZDPeer.PeerStatus
    let isCheckInOverdue: Bool
    var distanceFromUserM: Double?

    var statusBadgeColor: Color {
        if peerStatus == .sos { return .red }
        if isCheckInOverdue   { return .orange }
        if peerStatus == .offline { return .gray }
        if peerStatus == .away    { return .yellow }
        return .green
    }

    var statusLabel: String {
        if peerStatus == .sos     { return "SOS" }
        if isCheckInOverdue       { return "OVERDUE" }
        if peerStatus == .offline { return "Offline" }
        if peerStatus == .away    { return "Away" }
        return "Online"
    }
}

// MARK: - SortOption

enum BoardSortOption: String, CaseIterable {
    case distance = "Distance"
    case status   = "Status"
    case lastSeen = "Last Seen"
}

// MARK: - StatusBoardView

struct StatusBoardView: View {
    @ObservedObject private var mesh = MeshService.shared
    @ObservedObject private var checkIn = CheckInSystem.shared
    @State private var sortOption: BoardSortOption = .status
    @Environment(\.dismiss) private var dismiss

    private var entries: [BoardEntry] {
        let userLoc = LocationManager.shared.currentLocation.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
        }

        var list = mesh.peers.map { peer -> BoardEntry in
            let overdue = checkIn.peerStatuses.first(where: {
                $0.callsign == peer.name
            })?.isOverdue ?? false

            let distM: Double? = {
                guard let ul = userLoc, let pl = peer.location else { return nil }
                return ul.distance(from: CLLocation(latitude: pl.latitude, longitude: pl.longitude))
            }()

            return BoardEntry(
                id: peer.id,
                name: peer.name,
                location: peer.location,
                lastSeen: peer.lastSeen,
                batteryLevel: peer.batteryLevel,
                peerStatus: peer.status,
                isCheckInOverdue: overdue,
                distanceFromUserM: distM
            )
        }

        switch sortOption {
        case .distance:
            list.sort {
                let a = $0.distanceFromUserM ?? Double.greatestFiniteMagnitude
                let b = $1.distanceFromUserM ?? Double.greatestFiniteMagnitude
                return a < b
            }
        case .status:
            // SOS → Overdue → Offline → Away → Online
            list.sort { statusPriority($0) < statusPriority($1) }
        case .lastSeen:
            list.sort { $0.lastSeen > $1.lastSeen }
        }

        return list
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if mesh.peers.isEmpty {
                    emptyState
                } else {
                    boardList
                }
            }
            .navigationTitle("Team Status")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Sort", selection: $sortOption) {
                        ForEach(BoardSortOption.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.menu)
                    .foregroundColor(ZDDesign.cyanAccent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 44)).foregroundColor(.secondary)
            Text("No Peers Connected").font(.headline)
            Text("Start mesh networking to see team status.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }.padding()
    }

    // MARK: - Board List

    private var boardList: some View {
        ScrollView {
            VStack(spacing: 10) {
                summaryBar
                ForEach(entries) { entry in
                    BoardEntryRow(entry: entry)
                }
            }
            .padding()
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 16) {
            summaryCell("\(mesh.peers.filter { $0.status == .online }.count)", label: "online", color: .green)
            Divider().frame(height: 36)
            summaryCell("\(mesh.peers.filter { $0.status == .away }.count)", label: "away", color: .yellow)
            Divider().frame(height: 36)
            summaryCell("\(mesh.peers.filter { $0.status == .sos }.count)", label: "SOS", color: .red)
            Divider().frame(height: 36)
            summaryCell("\(checkIn.overdueCheckIns.count)", label: "overdue", color: .orange)
            Spacer()
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(10)
    }

    private func summaryCell(_ value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.bold().monospaced()).foregroundColor(color)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }

    // MARK: - Sort Priority

    private func statusPriority(_ e: BoardEntry) -> Int {
        if e.peerStatus == .sos     { return 0 }
        if e.isCheckInOverdue       { return 1 }
        if e.peerStatus == .offline { return 2 }
        if e.peerStatus == .away    { return 3 }
        return 4
    }
}

// MARK: - Board Entry Row

struct BoardEntryRow: View {
    let entry: BoardEntry

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator dot
            Circle()
                .fill(entry.statusBadgeColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(entry.name)
                        .font(.subheadline.bold())
                        .foregroundColor(ZDDesign.pureWhite)
                    Spacer()
                    Text(entry.statusLabel)
                        .font(.caption.bold())
                        .foregroundColor(entry.statusBadgeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(entry.statusBadgeColor.opacity(0.15))
                        .cornerRadius(6)
                }

                HStack(spacing: 12) {
                    // Last seen
                    Label(entry.lastSeen.formatted(.relative(presentation: .numeric)), systemImage: "clock")
                        .font(.caption)

                    // Battery
                    if let bat = entry.batteryLevel {
                        Label("\(bat)%", systemImage: batteryIcon(bat))
                            .font(.caption)
                            .foregroundColor(bat < 20 ? .red : .secondary)
                    }

                    // Distance
                    if let d = entry.distanceFromUserM {
                        let distStr = d >= 1000
                            ? String(format: "%.1fkm", d / 1000)
                            : String(format: "%.0fm", d)
                        Label(distStr, systemImage: "location")
                            .font(.caption)
                    }
                }
                .foregroundColor(.secondary)

                // Coordinates if available
                if let loc = entry.location {
                    Text(String(format: "%.5f, %.5f", loc.latitude, loc.longitude))
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(10)
        .overlay(
            entry.peerStatus == .sos
                ? RoundedRectangle(cornerRadius: 10).stroke(Color.red, lineWidth: 1.5)
                : nil
        )
    }

    private func batteryIcon(_ level: Int) -> String {
        switch level {
        case 75...: return "battery.100"
        case 50..<75: return "battery.75"
        case 25..<50: return "battery.25"
        default: return "battery.0"
        }
    }
}
