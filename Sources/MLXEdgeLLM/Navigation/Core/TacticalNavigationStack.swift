// TacticalNavigationStack.swift — Main navigation orchestrator (Boeing 3-layer pattern)

import Foundation
import Observation

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
            stop()
            status = .completed
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
}
