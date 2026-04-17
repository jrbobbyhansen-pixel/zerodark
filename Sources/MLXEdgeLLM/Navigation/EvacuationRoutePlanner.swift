// EvacuationRoutePlanner.swift — Terrain-aware evacuation route planning
// A* pathfinding with slope penalty from TerrainEngine, hazard avoidance
// Fully offline — uses cached SRTM elevation data only

import Foundation
import SwiftUI
import CoreLocation

// MARK: - Route Result

struct EvacRoute: Identifiable {
    let id = UUID()
    let waypoints: [CLLocationCoordinate2D]
    let totalDistanceM: Double
    let estimatedTimeMin: Double
    let maxSlopeDeg: Double
    let elevationGainM: Double
    let difficulty: RouteDifficulty
    let avoidsHazards: Bool
    let label: String
}

// MARK: - Hazard Zone

struct HazardZone: Identifiable {
    let id = UUID()
    let center: CLLocationCoordinate2D
    let radiusM: Double
    let description: String
}

// MARK: - A* Grid Node

private struct GridNode: Hashable {
    let row: Int
    let col: Int
}

private struct PathNode: Comparable {
    let node: GridNode
    let gCost: Double
    let hCost: Double
    var fCost: Double { gCost + hCost }
    let parent: GridNode?

    static func < (lhs: PathNode, rhs: PathNode) -> Bool { lhs.fCost < rhs.fCost }
}

// MARK: - EvacuationRoutePlanner

@MainActor
final class EvacuationRoutePlanner: ObservableObject {
    static let shared = EvacuationRoutePlanner()

    @Published var routes: [EvacRoute] = []
    @Published var isCalculating = false
    @Published var hazardZones: [HazardZone] = []

    private let terrain = TerrainEngine.shared
    private let gridSpacingM: Double = 50

    private init() {}

    func addHazard(center: CLLocationCoordinate2D, radiusM: Double, description: String) {
        hazardZones.append(HazardZone(center: center, radiusM: radiusM, description: description))
    }

    func removeHazard(_ hazard: HazardZone) {
        hazardZones.removeAll { $0.id == hazard.id }
    }

    // MARK: - Calculate Routes

    func calculateRoutes(from start: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async {
        isCalculating = true
        defer { isCalculating = false }
        routes = []

        if let primary = await computeRoute(from: start, to: destination, avoidHazards: true, label: "Primary") {
            routes.append(primary)
        }
        if let alternate = await computeRoute(from: start, to: destination, avoidHazards: false, label: "Alternate") {
            if routes.isEmpty || alternate.totalDistanceM != routes.first?.totalDistanceM {
                routes.append(alternate)
            }
        }
        AuditLogger.shared.log(.routeCalculated, detail: "evac_routes:\(routes.count)")
    }

    // MARK: - A* Pathfinding

    private func computeRoute(from start: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, avoidHazards: Bool, label: String) async -> EvacRoute? {
        let directDistM = CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))

        if directDistM < 500 {
            return buildDirectRoute(from: start, to: destination, label: label)
        }

        let latRange = abs(destination.latitude - start.latitude)
        let lonRange = abs(destination.longitude - start.longitude)
        let padding = 0.2
        let minLat = min(start.latitude, destination.latitude) - latRange * padding
        let maxLat = max(start.latitude, destination.latitude) + latRange * padding
        let minLon = min(start.longitude, destination.longitude) - lonRange * padding
        let maxLon = max(start.longitude, destination.longitude) + lonRange * padding

        let degPerMeterLat = 1.0 / 111_320.0
        let degPerMeterLon = 1.0 / (111_320.0 * cos(start.latitude * .pi / 180))
        let latStep = gridSpacingM * degPerMeterLat
        let lonStep = gridSpacingM * degPerMeterLon

        let effectiveRows = min(Int((maxLat - minLat) / latStep), 200)
        let effectiveCols = min(Int((maxLon - minLon) / lonStep), 200)

        let startNode = GridNode(row: Int((start.latitude - minLat) / latStep), col: Int((start.longitude - minLon) / lonStep))
        let goalNode = GridNode(row: Int((destination.latitude - minLat) / latStep), col: Int((destination.longitude - minLon) / lonStep))

        func coordFor(_ node: GridNode) -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: minLat + Double(node.row) * latStep, longitude: minLon + Double(node.col) * lonStep)
        }

        func heuristic(_ a: GridNode, _ b: GridNode) -> Double {
            let ca = coordFor(a), cb = coordFor(b)
            return CLLocation(latitude: ca.latitude, longitude: ca.longitude)
                .distance(from: CLLocation(latitude: cb.latitude, longitude: cb.longitude))
        }

        func moveCost(_ from: GridNode, _ to: GridNode) -> Double {
            let toCoord = coordFor(to)
            let fromCoord = coordFor(from)
            let dist = CLLocation(latitude: fromCoord.latitude, longitude: fromCoord.longitude)
                .distance(from: CLLocation(latitude: toCoord.latitude, longitude: toCoord.longitude))

            var slopePenalty = 1.0
            if let slope = terrain.slopeAt(coordinate: toCoord) {
                if slope > 30 { slopePenalty = 4.0 }
                else if slope > 20 { slopePenalty = 2.5 }
                else if slope > 10 { slopePenalty = 1.5 }
            }

            var hazardPenalty = 1.0
            if avoidHazards {
                for hz in hazardZones {
                    let distToHz = CLLocation(latitude: toCoord.latitude, longitude: toCoord.longitude)
                        .distance(from: CLLocation(latitude: hz.center.latitude, longitude: hz.center.longitude))
                    if distToHz < hz.radiusM { hazardPenalty = 100.0; break }
                    else if distToHz < hz.radiusM * 1.5 { hazardPenalty = 3.0 }
                }
            }

            return dist * slopePenalty * hazardPenalty
        }

        var openSet: [PathNode] = [PathNode(node: startNode, gCost: 0, hCost: heuristic(startNode, goalNode), parent: nil)]
        var closedSet: Set<GridNode> = []
        var cameFrom: [GridNode: GridNode] = [:]
        var gScores: [GridNode: Double] = [startNode: 0]

        let neighbors = [(-1,-1),(-1,0),(-1,1),(0,-1),(0,1),(1,-1),(1,0),(1,1)]

        while !openSet.isEmpty {
            openSet.sort()
            let current = openSet.removeFirst()

            if current.node == goalNode {
                var path: [CLLocationCoordinate2D] = [coordFor(goalNode)]
                var node = goalNode
                while let prev = cameFrom[node] { path.append(coordFor(prev)); node = prev }
                path.reverse()
                return buildRoute(waypoints: path, label: label)
            }

            closedSet.insert(current.node)

            for (dr, dc) in neighbors {
                let neighbor = GridNode(row: current.node.row + dr, col: current.node.col + dc)
                guard neighbor.row >= 0, neighbor.row < effectiveRows,
                      neighbor.col >= 0, neighbor.col < effectiveCols,
                      !closedSet.contains(neighbor) else { continue }

                let tentativeG = current.gCost + moveCost(current.node, neighbor)
                if tentativeG < (gScores[neighbor] ?? .infinity) {
                    gScores[neighbor] = tentativeG
                    cameFrom[neighbor] = current.node
                    openSet.append(PathNode(node: neighbor, gCost: tentativeG, hCost: heuristic(neighbor, goalNode), parent: current.node))
                }
            }

            if closedSet.count > 10000 { break }
        }

        return buildDirectRoute(from: start, to: destination, label: label)
    }

    // MARK: - Route Building

    private func buildRoute(waypoints: [CLLocationCoordinate2D], label: String) -> EvacRoute? {
        guard waypoints.count >= 2 else { return nil }
        let difficulty = terrain.routeDifficultyScore(route: waypoints)
        var totalDist = 0.0
        for i in 1..<waypoints.count {
            totalDist += CLLocation(latitude: waypoints[i-1].latitude, longitude: waypoints[i-1].longitude)
                .distance(from: CLLocation(latitude: waypoints[i].latitude, longitude: waypoints[i].longitude))
        }

        let speedKmH: Double
        switch difficulty.classification {
        case .easy: speedKmH = 5.0; case .moderate: speedKmH = 4.0
        case .difficult: speedKmH = 3.0; case .veryDifficult: speedKmH = 2.0; case .extreme: speedKmH = 1.5
        }

        return EvacRoute(waypoints: waypoints, totalDistanceM: totalDist,
                         estimatedTimeMin: (totalDist / 1000.0) / speedKmH * 60.0,
                         maxSlopeDeg: difficulty.maxSlopeDeg, elevationGainM: difficulty.elevationGainM,
                         difficulty: difficulty, avoidsHazards: !hazardZones.isEmpty, label: label)
    }

    private func buildDirectRoute(from start: CLLocationCoordinate2D, to dest: CLLocationCoordinate2D, label: String) -> EvacRoute? {
        var waypoints: [CLLocationCoordinate2D] = []
        for i in 0...20 {
            let frac = Double(i) / 20.0
            waypoints.append(CLLocationCoordinate2D(
                latitude: start.latitude + (dest.latitude - start.latitude) * frac,
                longitude: start.longitude + (dest.longitude - start.longitude) * frac))
        }
        return buildRoute(waypoints: waypoints, label: label)
    }
}

// MARK: - EvacuationRoutePlannerView

struct EvacuationRoutePlannerView: View {
    @ObservedObject private var planner = EvacuationRoutePlanner.shared
    @State private var destLat = ""
    @State private var destLon = ""

    var body: some View {
        Form {
            Section("Destination") {
                HStack {
                    TextField("Latitude", text: $destLat).keyboardType(.decimalPad)
                    TextField("Longitude", text: $destLon).keyboardType(.decimalPad)
                }
                Button {
                    guard let lat = Double(destLat), let lon = Double(destLon) else { return }
                    let start = LocationManager.shared.lastKnownLocation
                        ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
                    Task { await planner.calculateRoutes(from: start, to: CLLocationCoordinate2D(latitude: lat, longitude: lon)) }
                } label: {
                    Label("Calculate Routes", systemImage: "arrow.triangle.turn.up.right.diamond.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(ZDDesign.cyanAccent)
                .disabled(destLat.isEmpty || destLon.isEmpty || planner.isCalculating)
            }

            if planner.isCalculating {
                Section { ProgressView("Computing terrain-aware routes...") }
            }

            ForEach(planner.routes) { route in
                Section("\(route.label) Route") {
                    LabeledContent("Distance", value: String(format: "%.1f km", route.totalDistanceM / 1000))
                    LabeledContent("Time", value: String(format: "%.0f min", route.estimatedTimeMin))
                    LabeledContent("Max Slope", value: String(format: "%.0f°", route.maxSlopeDeg))
                    LabeledContent("Elev Gain", value: String(format: "%.0f m", route.elevationGainM))
                    HStack {
                        Text("Difficulty"); Spacer()
                        Text(route.difficulty.classification.rawValue).font(.caption.bold())
                    }
                }
            }
        }
        .navigationTitle("Evacuation Routes")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview { NavigationStack { EvacuationRoutePlannerView() } }
