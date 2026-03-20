// PurePursuitController.swift — Pure Pursuit steering controller (Boeing pattern)

import MapKit
import Foundation

/// Pure Pursuit controller for path following
public class PurePursuitController: NavigationControllerProtocol {
    private let lookaheadDistance: Double = 5.0  // meters
    private let maxTurnRate: Double = 45.0  // degrees per second
    private let pidKp: Double = 1.0
    private let pidKd: Double = 0.1

    private var lastHeadingError: Double = 0.0

    public init() {}

    /// Compute steering command
    public func step(from pose: NavPose, following path: NavPath) -> NavCommand {
        // Find closest point on path
        var closestIdx = 0
        var closestDist = Double.infinity

        for i in 0..<path.waypoints.count {
            let dist = pose.coordinate.distance(to: path.waypoints[i].coordinate)
            if dist < closestDist {
                closestDist = dist
                closestIdx = i
            }
        }

        // Find lookahead point
        var lookaheadIdx = closestIdx
        var accumulatedDist = 0.0

        while lookaheadIdx < path.waypoints.count - 1 && accumulatedDist < lookaheadDistance {
            let segDist = path.waypoints[lookaheadIdx].coordinate.distance(
                to: path.waypoints[lookaheadIdx + 1].coordinate
            )
            accumulatedDist += segDist
            if accumulatedDist >= lookaheadDistance {
                break
            }
            lookaheadIdx += 1
        }

        let lookaheadPoint = path.waypoints[lookaheadIdx].coordinate

        // Compute desired heading to lookahead point
        let dlat = lookaheadPoint.latitude - pose.coordinate.latitude
        let dlon = lookaheadPoint.longitude - pose.coordinate.longitude
        var desiredHeading = atan2(dlon, dlat) * 180.0 / .pi
        if desiredHeading < 0 {
            desiredHeading += 360
        }

        // PID control for heading error
        var headingError = desiredHeading - pose.heading
        if headingError > 180 {
            headingError -= 360
        } else if headingError < -180 {
            headingError += 360
        }

        let turnRate = pidKp * headingError + pidKd * (headingError - lastHeadingError)
        lastHeadingError = headingError

        // Cap turn rate
        let clampedTurnRate = max(-maxTurnRate, min(maxTurnRate, turnRate))

        // Desired speed (reduce when turning sharply)
        let speedReduction = max(0, 1.0 - abs(headingError) / 90.0)
        let desiredSpeed = pose.speed * speedReduction

        return NavCommand(
            desiredSpeed: desiredSpeed,
            desiredHeading: desiredHeading,
            turnRate: clampedTurnRate
        )
    }
}
