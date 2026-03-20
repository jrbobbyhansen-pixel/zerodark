// NavigationInterface.swift — Protocol interfaces for navigation layers (Boeing modular pattern)

import Foundation

/// Path planning protocol — generates initial path from start to goal
public protocol PathPlannerProtocol {
    func plan(from start: NavPose, to goal: NavWaypoint, using map: GridMap) async -> NavPath?
}

/// Trajectory optimizer protocol — smooths and optimizes planned path
public protocol TrajectoryOptimizerProtocol {
    func optimize(path: NavPath, around map: GridMap) -> NavPath
}

/// Navigation controller protocol — generates steering commands to follow path
public protocol NavigationControllerProtocol {
    func step(from pose: NavPose, following path: NavPath) -> NavCommand
}
