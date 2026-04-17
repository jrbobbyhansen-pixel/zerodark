// MessageQueue.swift — DTN store-and-forward queue viewer
// Shows pending/sent/failed bundles. Retry failed, priority reorder, clear delivered.

import Foundation
import SwiftUI

// MARK: - QueuedMessage (view model wrapping DTNBundle)

struct QueuedMessage: Identifiable {
    let id: UUID
    let bundle: DTNBundle
    var displayStatus: QueueStatus
    var priority: DTNBundle.BundlePriority { bundle.priority }
    var payloadPreview: String {
        String(data: bundle.payload, encoding: .utf8)?.prefix(120).description ?? "<binary \(bundle.payload.count)B>"
    }

    enum QueueStatus: String, CaseIterable {
        case pending   = "Pending"
        case delivered = "Delivered"
        case failed    = "Failed"

        var color: Color {
            switch self {
            case .pending:   return .yellow
            case .delivered: return .green
            case .failed:    return .red
            }
        }

        var icon: String {
            switch self {
            case .pending:   return "clock.fill"
            case .delivered: return "checkmark.circle.fill"
            case .failed:    return "xmark.circle.fill"
            }
        }
    }
}

// MARK: - MessageQueueManager

@MainActor
final class MessageQueueManager: ObservableObject {
    static let shared = MessageQueueManager()

    @Published var messages: [QueuedMessage] = []
    @Published var isLoading = false

    private let maxAttempts = 10

    private init() {
        Task { await reload() }
    }

    // MARK: - Load

    func reload() async {
        isLoading = true
        let buffer = DTNBuffer.shared
        let allRaw = await withCheckedContinuation { cont in
            Task {
                // DTNBuffer doesn't expose getAll directly, pull pending + delivered separately
                let pending = (try? await buffer.getPendingBundles()) ?? []
                cont.resume(returning: pending)
            }
        }

        // Categorize
        var result: [QueuedMessage] = []
        for bundle in allRaw {
            let status: QueuedMessage.QueueStatus
            if bundle.isDelivered {
                status = .delivered
            } else if bundle.isExpired || bundle.deliveryAttempts >= maxAttempts {
                status = .failed
            } else {
                status = .pending
            }
            result.append(QueuedMessage(id: bundle.id, bundle: bundle, displayStatus: status))
        }

        // Sort: priority desc, then createdAt asc
        messages = result.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.bundle.createdAt < $1.bundle.createdAt
        }
        isLoading = false
    }

    // MARK: - Retry Failed

    /// Re-enqueue a failed bundle: marks original delivered, creates new bundle with reset attempts.
    func retry(_ message: QueuedMessage) async {
        let buffer = DTNBuffer.shared
        // Retire old (mark delivered so it will be pruned)
        try? await buffer.markDelivered(message.id)

        // Create fresh bundle
        let fresh = DTNBundle(
            destination: message.bundle.destination,
            payload: message.bundle.payload,
            priority: message.bundle.priority,
            ttl: message.bundle.expiresAt.timeIntervalSinceNow
        )
        try? await buffer.store(fresh)
        await reload()
    }

    // MARK: - Clear Delivered

    func clearDelivered() async {
        await DTNBuffer.shared.pruneDelivered(olderThan: 0)
        await reload()
    }

    // MARK: - Enqueue (convenience for new messages)

    func enqueue(text: String, destination: String = "all", priority: DTNBundle.BundlePriority = .normal) async {
        guard let data = text.data(using: .utf8) else { return }
        let bundle = DTNBundle(destination: destination, payload: data, priority: priority)
        try? await DTNBuffer.shared.store(bundle)
        await reload()
    }
}

// MARK: - MessageQueueView

struct MessageQueueView: View {
    @ObservedObject private var manager = MessageQueueManager.shared
    @ObservedObject private var delivery = DTNDeliveryManager.shared
    @State private var filterStatus: QueuedMessage.QueueStatus? = nil
    @State private var showCompose = false
    @Environment(\.dismiss) private var dismiss

    private var filtered: [QueuedMessage] {
        guard let f = filterStatus else { return manager.messages }
        return manager.messages.filter { $0.displayStatus == f }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    summaryBar
                    filterChips
                    if manager.isLoading {
                        ProgressView().tint(ZDDesign.cyanAccent).padding(40)
                        Spacer()
                    } else if filtered.isEmpty {
                        emptyState
                    } else {
                        queueList
                    }
                }
            }
            .navigationTitle("DTN Message Queue")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            Task { await manager.clearDelivered() }
                        } label: {
                            Image(systemName: "trash.slash.fill")
                                .foregroundColor(ZDDesign.safetyYellow)
                        }
                        Button {
                            showCompose = true
                        } label: {
                            Image(systemName: "plus").foregroundColor(ZDDesign.cyanAccent)
                        }
                        Button {
                            Task { await manager.reload() }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath").foregroundColor(ZDDesign.cyanAccent)
                        }
                    }
                }
            }
            .sheet(isPresented: $showCompose) {
                ComposeMessageSheet { text, dest, priority in
                    Task {
                        await manager.enqueue(text: text, destination: dest, priority: priority)
                        showCompose = false
                    }
                }
            }
            .task { await manager.reload() }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack(spacing: 16) {
            let pending = manager.messages.filter { $0.displayStatus == .pending }.count
            let delivered = manager.messages.filter { $0.displayStatus == .delivered }.count
            let failed = manager.messages.filter { $0.displayStatus == .failed }.count

            summaryPill(count: pending, label: "Pending", color: .yellow)
            summaryPill(count: delivered, label: "Delivered", color: .green)
            summaryPill(count: failed, label: "Failed", color: .red)

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(delivery.isRunning ? ZDDesign.successGreen : ZDDesign.mediumGray)
                    .frame(width: 6, height: 6)
                Text(delivery.isRunning ? "Delivery On" : "Delivery Off")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(ZDDesign.darkCard)
    }

    private func summaryPill(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.caption.bold()).foregroundColor(count > 0 ? color : .secondary)
            Text(label)
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(nil, label: "All")
                ForEach(QueuedMessage.QueueStatus.allCases, id: \.self) { s in
                    filterChip(s, label: s.rawValue)
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
    }

    private func filterChip(_ status: QueuedMessage.QueueStatus?, label: String) -> some View {
        let isActive = filterStatus == status
        let color: Color = status?.color ?? ZDDesign.cyanAccent
        return Button {
            filterStatus = status
        } label: {
            Text(label)
                .font(.caption.bold())
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(isActive ? color : ZDDesign.darkCard)
                .foregroundColor(isActive ? .black : ZDDesign.pureWhite)
                .cornerRadius(8)
        }
    }

    // MARK: - Queue List

    private var queueList: some View {
        List {
            ForEach(filtered) { msg in
                MessageRow(message: msg)
                    .listRowBackground(ZDDesign.darkCard)
                    .swipeActions(edge: .leading) {
                        if msg.displayStatus == .failed {
                            Button {
                                Task { await manager.retry(msg) }
                            } label: {
                                Label("Retry", systemImage: "arrow.counterclockwise")
                            }
                            .tint(.orange)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if msg.displayStatus == .delivered {
                            Button(role: .destructive) {
                                Task {
                                    try? await DTNBuffer.shared.markDelivered(msg.id)
                                    await manager.reload()
                                }
                            } label: {
                                Label("Clear", systemImage: "trash")
                            }
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray").font(.system(size: 44)).foregroundColor(.secondary)
            Text("Queue Empty").font(.headline)
            Text(filterStatus == nil ? "No messages in the DTN queue." : "No \(filterStatus!.rawValue.lowercased()) messages.")
                .font(.caption).foregroundColor(.secondary)
            Spacer()
        }
    }
}

// MARK: - Message Row

struct MessageRow: View {
    let message: QueuedMessage
    @ObservedObject private var manager = MessageQueueManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Priority badge
                Text(priorityLabel(message.priority))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(priorityColor(message.priority))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(priorityColor(message.priority).opacity(0.2))
                    .cornerRadius(4)

                // Status badge
                Label(message.displayStatus.rawValue, systemImage: message.displayStatus.icon)
                    .font(.caption2.bold())
                    .foregroundColor(message.displayStatus.color)

                Spacer()

                // Attempts
                if message.bundle.deliveryAttempts > 0 {
                    Text("\(message.bundle.deliveryAttempts) attempts")
                        .font(.caption2).foregroundColor(.secondary)
                }

                // Retry button for failed
                if message.displayStatus == .failed {
                    Button {
                        Task { await manager.retry(message) }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }

            Text(message.payloadPreview)
                .font(.subheadline).foregroundColor(ZDDesign.pureWhite).lineLimit(2)

            HStack(spacing: 12) {
                Label(message.bundle.destination, systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption2).foregroundColor(.secondary)
                Label(message.bundle.createdAt.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                    .font(.caption2).foregroundColor(.secondary)
                if message.bundle.isExpired {
                    Text("EXPIRED").font(.system(size: 9, weight: .bold)).foregroundColor(.red)
                } else {
                    Text("exp \(message.bundle.expiresAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func priorityLabel(_ p: DTNBundle.BundlePriority) -> String {
        switch p {
        case .bulk:      return "BULK"
        case .normal:    return "NORMAL"
        case .expedited: return "EXPEDITED"
        case .critical:  return "CRITICAL"
        }
    }

    private func priorityColor(_ p: DTNBundle.BundlePriority) -> Color {
        switch p {
        case .bulk:      return .gray
        case .normal:    return .cyan
        case .expedited: return .orange
        case .critical:  return .red
        }
    }
}

// MARK: - Compose Message Sheet

struct ComposeMessageSheet: View {
    let onSend: (String, String, DTNBundle.BundlePriority) -> Void

    @State private var text: String = ""
    @State private var destination: String = "all"
    @State private var priority: DTNBundle.BundlePriority = .normal
    @ObservedObject private var mesh = MeshService.shared
    @Environment(\.dismiss) private var dismiss

    private var destinations: [String] {
        var d = ["all"]
        d.append(contentsOf: mesh.peers.map(\.id))
        return d
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Form {
                    Section("Message") {
                        TextField("Message content", text: $text, axis: .vertical)
                            .lineLimit(3...8)
                            .foregroundColor(ZDDesign.pureWhite)
                    }
                    .listRowBackground(ZDDesign.darkCard)

                    Section("Routing") {
                        Picker("Destination", selection: $destination) {
                            Text("Broadcast (all)").tag("all")
                            ForEach(mesh.peers) { peer in
                                Text(peer.name).tag(peer.id)
                            }
                        }
                        .colorScheme(.dark)

                        Picker("Priority", selection: $priority) {
                            Text("Bulk").tag(DTNBundle.BundlePriority.bulk)
                            Text("Normal").tag(DTNBundle.BundlePriority.normal)
                            Text("Expedited").tag(DTNBundle.BundlePriority.expedited)
                            Text("Critical").tag(DTNBundle.BundlePriority.critical)
                        }
                        .colorScheme(.dark)
                    }
                    .listRowBackground(ZDDesign.darkCard)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Queue Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Enqueue") { onSend(text, destination, priority) }
                        .fontWeight(.bold)
                        .disabled(text.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
