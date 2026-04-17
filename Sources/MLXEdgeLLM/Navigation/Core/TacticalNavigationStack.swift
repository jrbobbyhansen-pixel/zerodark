// TacticalNavigationStack.swift — Main navigation orchestrator (Boeing 3-layer pattern)

import Foundation
import Observation
import CoreLocation

/// Main navigation orchestrator: planner → optimizer → controller
@MainActor
public class TacticalNavigationStack: NSObject, ObservableObject {
    public static let shared = TacticalNavigationStack()

    @Published public var status: NavStatus = .idle
    @Published public var currentCommand: NavCommand?
    @Published public var currentPose: NavPose?

    private let planner: PathPlannerProtocol
    private let optimizer: TrajectoryOptimizerProtocol
    private let controller: NavigationControllerProtocol
    private let gridMap: GridMap

    private var currentPath: NavPath?
    private var navigationTimer: Timer?

    // MARK: - Long-Range Mission State (graph planning layer)
    @Published public private(set) var missionWaypoints: [GraphNode] = []
    @Published public private(set) var currentLegIndex: Int = 0
    @Published public private(set) var isMissionActive: Bool = false

    private override init() {
        // Initialize with default implementations
        self.planner = HybridAStarPlanner()
        self.optimizer = SimBandOptimizer()
        self.controller = PurePursuitController()
        self.gridMap = GridMap(width: 1000, height: 1000, resolution: 0.5)

        super.init()
    }

    /// Start navigation to destination
    public func start(destination: NavWaypoint) async {
        guard let currentPose = currentPose else {
            status = .error("No current position available")
            return
        }

        status = .planning

        // Step 1: Plan path
        guard let path = await planner.plan(from: currentPose, to: destination, using: gridMap) else {
            status = .error("Failed to plan path")
            return
        }

        // Step 2: Optimize trajectory
        let optimizedPath = optimizer.optimize(path: path, around: gridMap)
        currentPath = optimizedPath

        // Step 3: Begin control loop
        status = .executing(currentWaypoint: 0, totalWaypoints: optimizedPath.waypoints.count, distanceRemaining: optimizedPath.distanceMeters)

        navigationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.step()
            }
        }
    }

    /// Stop navigation
    public func stop() {
        navigationTimer?.invalidate()
        navigationTimer = nil
        status = .idle
        currentCommand = nil
    }

    /// Single control step
    private func step() async {
        guard let pose = currentPose, let path = currentPath else {
            return
        }

        let command = controller.step(from: pose, following: path)
        currentCommand = command

        // Check if we've completed the path
        guard let lastWaypoint = path.waypoints.last else { return }
        if pose.coordinate.distance(to: lastWaypoint.coordinate) < 5.0 {
            if isMissionActive {
                // Advance to next graph waypoint rather than stopping
                advanceToNextLeg()
            } else {
                stop()
                status = .completed
            }
        } else {
            // Update status with progress
            let distRemaining = calculateRemainingDistance(from: pose, in: path)
            if case .executing(let current, let total, _) = status {
                status = .executing(currentWaypoint: current, totalWaypoints: total, distanceRemaining: distRemaining)
            }
        }
    }

    private func calculateRemainingDistance(from pose: NavPose, in path: NavPath) -> Double {
        var remaining = 0.0
        var started = false

        for i in 0..<path.waypoints.count - 1 {
            let from = path.waypoints[i].coordinate
            let to = path.waypoints[i + 1].coordinate

            if !started {
                // Find current segment
                remaining += pose.coordinate.distance(to: to)
                started = true
            } else {
                remaining += from.distance(to: to)
            }
        }

        return max(0, remaining)
    }

    /// Update current pose (called from location services)
    public func updatePose(_ pose: NavPose) {
        self.currentPose = pose
    }

    // MARK: - Long-Range Mission (graph planning layer)

    /// Begin a multi-waypoint mission. The graph planner hands an ordered [GraphNode] list;
    /// HybridAStarPlanner handles local obstacle avoidance on each individual leg.
    /// - Parameter waypoints: Ordered nodes from NavigationGraph.findPath(from:to:).
    public func startMission(waypoints: [GraphNode]) {
        guard waypoints.count >= 2 else {
            // Single node: treat as a direct navigation destination
            if let node = waypoints.first {
                let dest = NavWaypoint(
                    coordinate: CLLocationCoordinate2D(
                        latitude: node.coordinate.latitude,
                        longitude: node.coordinate.longitude
                    ),
                    name: node.name
                )
                Task { await start(destination: dest) }
            }
            return
        }

        missionWaypoints = waypoints
        currentLegIndex = 0
        isMissionActive = true
        advanceToNextLeg()
    }

    /// Abort the active multi-waypoint mission and stop navigation.
    public func cancelMission() {
        isMissionActive = false
        missionWaypoints = []
        currentLegIndex = 0
        stop()
    }

    private func advanceToNextLeg() {
        // Skip the first leg if we're just starting (index 0 = current position node)
        let nextIndex = currentLegIndex + 1
        guard nextIndex < missionWaypoints.count else {
            missionComplete()
            return
        }

        currentLegIndex = nextIndex
        let targetNode = missionWaypoints[nextIndex]
        let dest = NavWaypoint(
            coordinate: CLLocationCoordinate2D(
                latitude: targetNode.coordinate.latitude,
                longitude: targetNode.coordinate.longitude
            ),
            name: targetNode.name
        )

        Task {
            await start(destination: dest)
        }
    }

    private func missionComplete() {
        isMissionActive = false
        stop()
        status = .completed
        missionWaypoints = []
        currentLegIndex = 0
    }
}
