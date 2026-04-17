// ResourceTracker.swift — Shared consumable tracking with consumption history and resupply planning
// Tracks: water, food, batteries, medical, ammo. Logs consumption events.
// Alerts on low levels via mesh + local notification. Projects days remaining.

import Foundation
import SwiftUI
import UserNotifications

// MARK: - ResourceType

enum ResourceType: String, CaseIterable, Codable, Identifiable {
    case water          = "Water"
    case food           = "Food"
    case batteries      = "Batteries"
    case medicalSupplies = "Medical Supplies"
    case ammo           = "Ammunition"

    var id: String { rawValue }

    var unit: String {
        switch self {
        case .water:           return "L"
        case .food:            return "rations"
        case .batteries:       return "cells"
        case .medicalSupplies: return "kits"
        case .ammo:            return "rds"
        }
    }

    var icon: String {
        switch self {
        case .water:           return "drop.fill"
        case .food:            return "fork.knife"
        case .batteries:       return "battery.100"
        case .medicalSupplies: return "cross.case.fill"
        case .ammo:            return "circle.hexagongrid.fill"
        }
    }

    var color: Color {
        switch self {
        case .water:           return .blue
        case .food:            return .green
        case .batteries:       return .yellow
        case .medicalSupplies: return .red
        case .ammo:            return .orange
        }
    }

    /// Low-level threshold as fraction of max (20%)
    var lowFraction: Double { 0.20 }
}

// MARK: - ConsumptionEvent

struct ConsumptionEvent: Identifiable, Codable {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var resourceType: ResourceType
    var amount: Double      // negative = consumed, positive = resupplied
    var note: String
    var reportedBy: String
}

// MARK: - ResourceItem

struct ResourceItem: Identifiable, Codable {
    var id: UUID = UUID()
    var type: ResourceType
    var current: Double
    var maximum: Double
    var dailyConsumptionRate: Double?  // per person per day, for projection

    var fraction: Double {
        guard maximum > 0 else { return 0 }
        return min(1, max(0, current / maximum))
    }

    var isLow: Bool { fraction <= type.lowFraction }

    var daysRemaining: Double? {
        guard let rate = dailyConsumptionRate, rate > 0, current > 0 else { return nil }
        return current / rate
    }
}

// MARK: - ResourceTrackerManager

@MainActor
final class ResourceTrackerManager: ObservableObject {
    static let shared = ResourceTrackerManager()

    @Published var items: [ResourceItem] = []
    @Published var history: [ConsumptionEvent] = []
    @Published var lowAlerts: [ResourceType] = []

    private let saveURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("resource_tracker.json")
    }()
    private let historyURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("resource_history.json")
    }()
    private let meshPrefix = "[resource-low]"

    private init() {
        load()
        if items.isEmpty { setupDefaults() }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Consumption / Resupply

    func consume(_ type: ResourceType, amount: Double, note: String = "") {
        guard amount > 0 else { return }
        if let i = items.firstIndex(where: { $0.type == type }) {
            items[i].current = max(0, items[i].current - amount)
            logEvent(ConsumptionEvent(
                resourceType: type, amount: -amount,
                note: note.isEmpty ? "Consumed" : note,
                reportedBy: AppConfig.deviceCallsign
            ))
            checkLowLevels()
        }
    }

    func resupply(_ type: ResourceType, amount: Double, note: String = "") {
        guard amount > 0 else { return }
        if let i = items.firstIndex(where: { $0.type == type }) {
            items[i].current = min(items[i].maximum, items[i].current + amount)
            logEvent(ConsumptionEvent(
                resourceType: type, amount: amount,
                note: note.isEmpty ? "Resupplied" : note,
                reportedBy: AppConfig.deviceCallsign
            ))
            checkLowLevels()
        }
    }

    func updateMax(_ type: ResourceType, max: Double) {
        if let i = items.firstIndex(where: { $0.type == type }) {
            items[i].maximum = max
            items[i].current = min(items[i].current, max)
            save()
        }
    }

    // MARK: - Low Level Detection

    private func checkLowLevels() {
        let newLow = items.filter(\.isLow).map(\.type)
        let newAlerts = newLow.filter { !lowAlerts.contains($0) }
        lowAlerts = newLow

        for type in newAlerts {
            fireAlert(for: type)
            broadcastLow(type)
        }
        save()
    }

    private func fireAlert(for type: ResourceType) {
        let content = UNMutableNotificationContent()
        content.title = "Low Resource: \(type.rawValue)"
        if let item = items.first(where: { $0.type == type }) {
            content.body = String(format: "%.0f %@ remaining (%.0f%%)", item.current, type.unit, item.fraction * 100)
        }
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: "resource.low.\(type.rawValue)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req) { _ in }

        NotificationCenter.default.post(
            name: Notification.Name("ZD.inAppAlert"),
            object: nil,
            userInfo: [
                "title": "Low Resource",
                "body": "\(type.rawValue) critically low",
                "severity": "warning"
            ]
        )
    }

    private func broadcastLow(_ type: ResourceType) {
        guard MeshService.shared.isActive else { return }
        MeshService.shared.sendText("\(meshPrefix)\(type.rawValue):LOW")
    }

    // MARK: - History

    private func logEvent(_ event: ConsumptionEvent) {
        history.insert(event, at: 0)
        if history.count > 500 { history = Array(history.prefix(500)) }
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: historyURL, options: .atomic)
        }
    }

    func historyFor(_ type: ResourceType) -> [ConsumptionEvent] {
        history.filter { $0.resourceType == type }
    }

    // MARK: - Resupply Projection

    /// Returns estimated days remaining for each resource based on last 3 days of history.
    func updateDailyRates() {
        let threeDaysAgo = Date().addingTimeInterval(-3 * 86400)
        for i in items.indices {
            let consumed = history.filter {
                $0.resourceType == items[i].type &&
                $0.amount < 0 &&
                $0.timestamp >= threeDaysAgo
            }.map { abs($0.amount) }.reduce(0, +)
            if consumed > 0 {
                items[i].dailyConsumptionRate = consumed / 3.0
            }
        }
        save()
    }

    // MARK: - Defaults

    private func setupDefaults() {
        items = [
            ResourceItem(type: .water,           current: 6.0,  maximum: 8.0,  dailyConsumptionRate: 3.0),
            ResourceItem(type: .food,            current: 6.0,  maximum: 9.0,  dailyConsumptionRate: 3.0),
            ResourceItem(type: .batteries,       current: 12.0, maximum: 20.0, dailyConsumptionRate: nil),
            ResourceItem(type: .medicalSupplies, current: 1.0,  maximum: 2.0,  dailyConsumptionRate: nil),
            ResourceItem(type: .ammo,            current: 210.0, maximum: 300.0, dailyConsumptionRate: nil)
        ]
        save()
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }

    private func load() {
        if let data = try? Data(contentsOf: saveURL),
           let loaded = try? JSONDecoder().decode([ResourceItem].self, from: data) {
            items = loaded
        }
        if let data = try? Data(contentsOf: historyURL),
           let loaded = try? JSONDecoder().decode([ConsumptionEvent].self, from: data) {
            history = loaded
        }
        lowAlerts = items.filter(\.isLow).map(\.type)
    }
}

// MARK: - ResourceTrackerView

struct ResourceTrackerView: View {
    @ObservedObject private var manager = ResourceTrackerManager.shared
    @State private var selectedType: ResourceType?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        // Low alerts banner
                        if !manager.lowAlerts.isEmpty {
                            alertBanner
                        }
                        // Resource cards
                        ForEach(manager.items) { item in
                            ResourceItemCard(item: item)
                                .onTapGesture { selectedType = item.type }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Resources")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        manager.updateDailyRates()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }
            .sheet(item: $selectedType) { type in
                ResourceDetailView(type: type)
                    .preferredColorScheme(.dark)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var alertBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
            Text("Low: \(manager.lowAlerts.map(\.rawValue).joined(separator: ", "))")
                .font(.caption.bold()).foregroundColor(.red)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - Resource Item Card

struct ResourceItemCard: View {
    let item: ResourceItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(item.type.rawValue, systemImage: item.type.icon)
                    .font(.subheadline.bold())
                    .foregroundColor(item.isLow ? .red : item.type.color)
                Spacer()
                if item.isLow {
                    Text("LOW").font(.caption2.bold()).foregroundColor(.red)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.red.opacity(0.15)).cornerRadius(4)
                }
                Text(String(format: "%.0f / %.0f %@", item.current, item.maximum, item.type.unit))
                    .font(.caption.monospaced()).foregroundColor(ZDDesign.pureWhite)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 8)
                    Capsule()
                        .fill(item.isLow ? Color.red : item.type.color)
                        .frame(width: geo.size.width * CGFloat(item.fraction), height: 8)
                }
            }
            .frame(height: 8)

            HStack {
                Text(String(format: "%.0f%%", item.fraction * 100))
                    .font(.caption2.monospaced()).foregroundColor(.secondary)
                Spacer()
                if let days = item.daysRemaining {
                    Text(days < 1 ? "<1 day remaining" : String(format: "~%.0f days remaining", days))
                        .font(.caption2).foregroundColor(days < 1 ? .red : days < 2 ? .orange : .secondary)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(10)
        .overlay(
            item.isLow ? RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.5), lineWidth: 1) : nil
        )
    }
}

// MARK: - Resource Detail View

struct ResourceDetailView: View {
    let type: ResourceType
    @ObservedObject private var manager = ResourceTrackerManager.shared
    @State private var consumeAmount: Double = 1
    @State private var resupplyAmount: Double = 1
    @State private var note: String = ""
    @Environment(\.dismiss) private var dismiss

    private var item: ResourceItem? { manager.items.first { $0.type == type } }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if let item { ResourceItemCard(item: item) }

                        // Quick actions
                        actionCard

                        // History
                        historySection
                    }
                    .padding()
                }
            }
            .navigationTitle(type.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } }
            }
        }
    }

    private var actionCard: some View {
        VStack(spacing: 12) {
            TextField("Note (optional)", text: $note).foregroundColor(ZDDesign.pureWhite)
                .padding(8).background(Color.white.opacity(0.06)).cornerRadius(8)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Consume").font(.caption.bold()).foregroundColor(.red)
                    HStack {
                        Stepper("\(Int(consumeAmount)) \(type.unit)", value: $consumeAmount, in: 1...100)
                            .font(.caption)
                        Button("Use") {
                            manager.consume(type, amount: consumeAmount, note: note)
                            note = ""
                        }
                        .font(.caption.bold()).foregroundColor(.black)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.red).cornerRadius(6)
                    }
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Resupply").font(.caption.bold()).foregroundColor(.green)
                    HStack {
                        Stepper("\(Int(resupplyAmount)) \(type.unit)", value: $resupplyAmount, in: 1...500)
                            .font(.caption)
                        Button("Add") {
                            manager.resupply(type, amount: resupplyAmount, note: note)
                            note = ""
                        }
                        .font(.caption.bold()).foregroundColor(.black)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.green).cornerRadius(6)
                    }
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(10)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History").font(.caption.bold()).foregroundColor(.secondary)
            let events = manager.historyFor(type).prefix(30)
            if events.isEmpty {
                Text("No history yet.").font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(Array(events)) { event in
                    HStack {
                        Image(systemName: event.amount < 0 ? "minus.circle" : "plus.circle")
                            .foregroundColor(event.amount < 0 ? .red : .green)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.note).font(.caption).foregroundColor(ZDDesign.pureWhite)
                            Text(event.reportedBy).font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(String(format: "%+.0f %@", event.amount, type.unit))
                                .font(.caption.monospaced())
                                .foregroundColor(event.amount < 0 ? .red : .green)
                            Text(event.timestamp, style: .relative)
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(10)
    }
}
