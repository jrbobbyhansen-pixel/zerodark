import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - MeshDiagnostics

class MeshDiagnostics: ObservableObject {
    @Published var packetLoss: [String: Double] = [:]
    @Published var latency: [String: Double] = [:]
    @Published var throughput: [String: Double] = [:]
    @Published var failingNodes: [String] = []
    @Published var historicalPerformance: [String: [PerformanceRecord]] = [:]

    private let networkManager: NetworkManager

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
        setupObservers()
    }

    private func setupObservers() {
        networkManager.$packetLoss.sink { [weak self] loss in
            self?.updatePacketLoss(loss)
        }.store(in: &cancellables)

        networkManager.$latency.sink { [weak self] latency in
            self?.updateLatency(latency)
        }.store(in: &cancellables)

        networkManager.$throughput.sink { [weak self] throughput in
            self?.updateThroughput(throughput)
        }.store(in: &cancellables)
    }

    private func updatePacketLoss(_ loss: [String: Double]) {
        packetLoss = loss
        identifyFailingNodes()
    }

    private func updateLatency(_ latency: [String: Double]) {
        latency = latency
        identifyFailingNodes()
    }

    private func updateThroughput(_ throughput: [String: Double]) {
        throughput = throughput
        identifyFailingNodes()
    }

    private func identifyFailingNodes() {
        failingNodes = packetLoss.filter { $0.value > 0.5 }.keys.map { String($0) }
    }

    func recordPerformance() {
        let timestamp = Date()
        for (node, loss) in packetLoss {
            let record = PerformanceRecord(timestamp: timestamp, packetLoss: loss, latency: latency[node] ?? 0, throughput: throughput[node] ?? 0)
            historicalPerformance[node, default: []].append(record)
        }
    }
}

// MARK: - PerformanceRecord

struct PerformanceRecord: Codable {
    let timestamp: Date
    let packetLoss: Double
    let latency: Double
    let throughput: Double
}

// MARK: - NetworkManager

class NetworkManager: ObservableObject {
    @Published var packetLoss: [String: Double] = [:]
    @Published var latency: [String: Double] = [:]
    @Published var throughput: [String: Double] = [:]

    func simulateNetworkMetrics() {
        // Simulate network metrics for demonstration purposes
        packetLoss = ["Node1": 0.1, "Node2": 0.6, "Node3": 0.2]
        latency = ["Node1": 20.0, "Node2": 150.0, "Node3": 30.0]
        throughput = ["Node1": 10.0, "Node2": 5.0, "Node3": 8.0]
    }
}

// MARK: - MeshDiagnosticsView

struct MeshDiagnosticsView: View {
    @StateObject private var diagnostics = MeshDiagnostics(networkManager: NetworkManager())

    var body: some View {
        VStack {
            Text("Mesh Network Diagnostics")
                .font(.largeTitle)
                .padding()

            List(diagnostics.packetLoss.keys, id: \.self) { node in
                HStack {
                    Text("Node \(node)")
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Packet Loss: \(diagnostics.packetLoss[node, default: 0.0], specifier: "%.2f")%")
                        Text("Latency: \(diagnostics.latency[node, default: 0.0], specifier: "%.2f") ms")
                        Text("Throughput: \(diagnostics.throughput[node, default: 0.0], specifier: "%.2f") Mbps")
                    }
                }
            }

            Button(action: {
                diagnostics.recordPerformance()
            }) {
                Text("Record Performance")
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .padding()
    }
}

// MARK: - Preview

struct MeshDiagnosticsView_Previews: PreviewProvider {
    static var previews: some View {
        MeshDiagnosticsView()
    }
}