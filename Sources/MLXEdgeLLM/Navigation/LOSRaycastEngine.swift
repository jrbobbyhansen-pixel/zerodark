// LOSRaycastEngine.swift — Line-of-sight raycast using DEM elevation data
// Samples TerrainEngine.shared along great circle path with earth curvature correction
// Returns visible/blocked segments for map rendering

import Foundation
import CoreLocation

// MARK: - LOS Result

struct LOSResult {
    let isVisible: Bool
    let obstructionPoint: CLLocationCoordinate2D?  // First obstruction, if any
    let segments: [LOSSegment]
    let observerElevation: Double
    let targetElevation: Double
}

struct LOSSegment {
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
    let isVisible: Bool
}

// MARK: - LOS Raycast Engine

final class LOSRaycastEngine {
    static let shared = LOSRaycastEngine()

    // Earth radius for curvature correction
    private let earthRadius: Double = 6_371_000.0  // meters
    private let defaultObserverHeight: Double = 1.8  // meters (standing person)
    private let defaultTargetHeight: Double = 0.0    // ground level

    private init() {}

    // MARK: - Raycast

    /// Compute line-of-sight between two coordinates using DEM data
    /// - Parameters:
    ///   - observer: Observer position
    ///   - target: Target position
    ///   - observerHeight: Height above ground (meters)
    ///   - targetHeight: Height above ground at target (meters)
    ///   - sampleCount: Number of elevation samples along the path
    /// - Returns: LOSResult with visibility and segment breakdown
    func computeLOS(
        from observer: CLLocationCoordinate2D,
        to target: CLLocationCoordinate2D,
        observerHeight: Double? = nil,
        targetHeight: Double? = nil,
        sampleCount: Int = 100
    ) -> LOSResult {
        let obsHeight = observerHeight ?? defaultObserverHeight
        let tgtHeight = targetHeight ?? defaultTargetHeight

        // Get observer and target elevations from DEM
        let obsElev = TerrainEngine.shared.elevationAt(coordinate: observer) ?? 0
        let tgtElev = TerrainEngine.shared.elevationAt(coordinate: target) ?? 0

        let obsTotal = obsElev + obsHeight
        let tgtTotal = tgtElev + tgtHeight

        // Total distance
        let totalDist = CLLocation(latitude: observer.latitude, longitude: observer.longitude)
            .distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude))

        guard totalDist > 0 && sampleCount > 1 else {
            return LOSResult(isVisible: true, obstructionPoint: nil, segments: [], observerElevation: obsElev, targetElevation: tgtElev)
        }

        // Sample points along the great circle path
        var segments: [LOSSegment] = []
        var currentVisible = true
        var segmentStart = observer
        var firstObstruction: CLLocationCoordinate2D?

        for i in 1..<sampleCount {
            let fraction = Double(i) / Double(sampleCount)

            // Interpolate coordinate along great circle
            let sampleCoord = interpolateCoordinate(from: observer, to: target, fraction: fraction)

            // Get terrain elevation at sample point
            let terrainElev = TerrainEngine.shared.elevationAt(coordinate: sampleCoord) ?? 0

            // Compute LOS height at this distance (linear interpolation + earth curvature)
            let sampleDist = totalDist * fraction
            let losHeight = obsTotal + (tgtTotal - obsTotal) * fraction

            // Earth curvature correction: drop = d² / (2R)
            let curvatureDrop = (sampleDist * (totalDist - sampleDist)) / (2.0 * earthRadius)
            let effectiveLOSHeight = losHeight - curvatureDrop

            // Is terrain blocking the LOS at this point?
            let isBlocked = terrainElev > effectiveLOSHeight

            if isBlocked != !currentVisible {
                // Segment boundary
                segments.append(LOSSegment(start: segmentStart, end: sampleCoord, isVisible: currentVisible))
                segmentStart = sampleCoord
                currentVisible = !isBlocked

                if isBlocked && firstObstruction == nil {
                    firstObstruction = sampleCoord
                }
            }
        }

        // Final segment
        segments.append(LOSSegment(start: segmentStart, end: target, isVisible: currentVisible))

        let isFullyVisible = firstObstruction == nil

        return LOSResult(
            isVisible: isFullyVisible,
            obstructionPoint: firstObstruction,
            segments: segments,
            observerElevation: obsElev,
            targetElevation: tgtElev
        )
    }

    // MARK: - Elevation Profile

    /// Compute elevation profile along a line — returns per-sample terrain vs LOS height
    func elevationProfile(
        from observer: CLLocationCoordinate2D,
        to target: CLLocationCoordinate2D,
        observerHeight: Double? = nil,
        targetHeight: Double? = nil,
        sampleCount: Int = 100
    ) -> [ElevationProfilePoint] {
        let obsHeight = observerHeight ?? defaultObserverHeight
        let tgtHeight = targetHeight ?? defaultTargetHeight

        let obsElev = TerrainEngine.shared.elevationAt(coordinate: observer) ?? 0
        let tgtElev = TerrainEngine.shared.elevationAt(coordinate: target) ?? 0
        let obsTotal = obsElev + obsHeight
        let tgtTotal = tgtElev + tgtHeight

        let totalDist = CLLocation(latitude: observer.latitude, longitude: observer.longitude)
            .distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude))

        guard totalDist > 0 && sampleCount > 1 else { return [] }

        var profile: [ElevationProfilePoint] = []
        var maxElevAngle = -Double.infinity

        for i in 1...sampleCount {
            let fraction = Double(i) / Double(sampleCount)
            let sampleDist = totalDist * fraction
            let sampleCoord = interpolateCoordinate(from: observer, to: target, fraction: fraction)
            let terrainElev = TerrainEngine.shared.elevationAt(coordinate: sampleCoord) ?? 0

            let losHeight = obsTotal + (tgtTotal - obsTotal) * fraction
            let curvatureDrop = (sampleDist * (totalDist - sampleDist)) / (2.0 * earthRadius)
            let effectiveLOSHeight = losHeight - curvatureDrop

            let elevAngle = atan2(terrainElev - obsTotal, sampleDist)
            let isBlocked = elevAngle > maxElevAngle ? false : true
            if elevAngle > maxElevAngle { maxElevAngle = elevAngle }

            profile.append(ElevationProfilePoint(
                distance: sampleDist,
                terrainElevation: terrainElev,
                losHeight: effectiveLOSHeight,
                isBlocked: terrainElev > effectiveLOSHeight
            ))
        }

        return profile
    }

    // MARK: - Viewshed (360° LOS)

    /// Compute viewshed — which areas are visible from a point
    /// Returns array of (coordinate, isVisible) for rendering as heat map
    /// Default resolution: 360 radials (1° each), 100 samples per radial
    func computeViewshed(
        from observer: CLLocationCoordinate2D,
        radius: Double = 2000,  // meters
        observerHeight: Double? = nil,
        resolution: Int = 360    // number of radial lines (every 1°)
    ) -> [(coordinate: CLLocationCoordinate2D, isVisible: Bool)] {
        var results: [(CLLocationCoordinate2D, Bool)] = []

        let obsHeight = observerHeight ?? defaultObserverHeight
        let angleStep = 360.0 / Double(resolution)

        for i in 0..<resolution {
            let bearing = Double(i) * angleStep

            // Compute target coordinate at radius along bearing
            let target = coordinateAtBearing(from: observer, bearing: bearing, distance: radius)

            let los = computeLOS(from: observer, to: target, observerHeight: obsHeight, sampleCount: 100)

            for segment in los.segments {
                results.append((segment.end, segment.isVisible))
            }
        }

        return results
    }

    // MARK: - Reciprocal Viewshed (Counter-Surveillance)

    /// Compute reciprocal viewshed — which points in the area can see the observer
    /// Critical for counter-surveillance: shows exposure zones the operator must avoid
    /// - Parameters:
    ///   - observer: Position to evaluate exposure for
    ///   - radius: Analysis radius in meters
    ///   - resolution: Angular resolution (default 360 — every 1°)
    /// - Returns: Array of (coordinate, canSeeObserver) — canSeeObserver=true means those
    ///            positions have LOS to the observer, i.e. the observer is exposed to them
    func computeReciprocalViewshed(
        observer: CLLocationCoordinate2D,
        radius: Double = 1500,
        resolution: Int = 360
    ) -> [(coordinate: CLLocationCoordinate2D, canSeeObserver: Bool)] {
        // Reciprocal viewshed = viewshed from observer, but semantics inverted:
        // "can see" means that location is visible FROM observer = observer is also
        // visible FROM that location (LOS is symmetric for terrain occlusion).
        // We compute normally and return the same data with the semantic label flipped.
        let viewshed = computeViewshed(from: observer, radius: radius, observerHeight: defaultObserverHeight, resolution: resolution)
        return viewshed.map { (coordinate: $0.coordinate, canSeeObserver: $0.isVisible) }
    }

    /// Compute combined viewshed for multiple observers — merged visibility
    /// - Parameters:
    ///   - observers: Array of observer positions (max 4 for performance)
    ///   - radius: Analysis radius in meters
    ///   - mode: .union (any observer can see) or .intersection (all observers can see)
    func computeMultiObserverViewshed(
        observers: [CLLocationCoordinate2D],
        radius: Double = 2000,
        mode: MultiObserverMode = .union
    ) async -> [(coordinate: CLLocationCoordinate2D, isVisible: Bool)] {
        let clamped = Array(observers.prefix(4))
        guard !clamped.isEmpty else { return [] }

        // Run all viewsheds concurrently
        var allViewsheds: [[(coordinate: CLLocationCoordinate2D, isVisible: Bool)]] = []

        await withTaskGroup(of: [(CLLocationCoordinate2D, Bool)].self) { group in
            for obs in clamped {
                group.addTask { [self] in
                    self.computeViewshed(from: obs, radius: radius, observerHeight: self.defaultObserverHeight)
                }
            }
            for await result in group {
                allViewsheds.append(result)
            }
        }

        guard let first = allViewsheds.first else { return [] }

        // Merge: build coordinate-keyed visibility
        // Using first viewshed's coordinates as the reference grid
        var merged: [(coordinate: CLLocationCoordinate2D, isVisible: Bool)] = []
        for (i, entry) in first.enumerated() {
            let coord = entry.coordinate
            let visibilities = allViewsheds.compactMap { vs -> Bool? in
                guard i < vs.count else { return nil }
                return vs[i].isVisible
            }
            let combined: Bool
            switch mode {
            case .union:        combined = visibilities.contains(true)
            case .intersection: combined = visibilities.allSatisfy { $0 }
            }
            merged.append((coordinate: coord, isVisible: combined))
        }

        return merged
    }

    enum MultiObserverMode {
        case union         // Visible if ANY observer can see it
        case intersection  // Visible only if ALL observers can see it
    }

    /// GPU-accelerated viewshed (delegates to ViewshedComputeEngine)
    func computeViewshedGPU(
        from observer: CLLocationCoordinate2D,
        radius: Double = 2000,
        observerHeight: Double = 1.8,
        resolution: Int = 360,
        samplesPerRadial: Int = 200
    ) async -> ViewshedResult? {
        await ViewshedComputeEngine.shared.computeViewshed(
            from: observer,
            radius: radius,
            observerHeight: observerHeight,
            resolution: resolution,
            samplesPerRadial: samplesPerRadial
        )
    }

    // MARK: - Helpers

    private func interpolateCoordinate(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        fraction: Double
    ) -> CLLocationCoordinate2D {
        let lat = start.latitude + (end.latitude - start.latitude) * fraction
        let lon = start.longitude + (end.longitude - start.longitude) * fraction
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func coordinateAtBearing(
        from origin: CLLocationCoordinate2D,
        bearing: Double,
        distance: Double
    ) -> CLLocationCoordinate2D {
        let lat1 = origin.latitude * .pi / 180.0
        let lon1 = origin.longitude * .pi / 180.0
        let brng = bearing * .pi / 180.0
        let d = distance / earthRadius

        let lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(brng))
        let lon2 = lon1 + atan2(sin(brng) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2))

        return CLLocationCoordinate2D(
            latitude: lat2 * 180.0 / .pi,
            longitude: lon2 * 180.0 / .pi
        )
    }
}
