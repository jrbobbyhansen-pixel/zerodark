import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - DroneSearchPatterns

class DroneSearchPatterns: ObservableObject {
    @Published var searchPattern: SearchPattern = .expandingSquare
    @Published var searchArea: MKCoordinateRegion
    @Published var currentLocation: CLLocationCoordinate2D
    @Published var coverageMap: [CLLocationCoordinate2D: Bool] = [:]

    init(searchArea: MKCoordinateRegion, currentLocation: CLLocationCoordinate2D) {
        self.searchArea = searchArea
        self.currentLocation = currentLocation
    }

    func startSearch() {
        switch searchPattern {
        case .expandingSquare:
            performExpandingSquareSearch()
        case .parallelTrack:
            performParallelTrackSearch()
        case .creepingLine:
            performCreepingLineSearch()
        }
    }

    private func performExpandingSquareSearch() {
        // Implementation for expanding square search pattern
    }

    private func performParallelTrackSearch() {
        // Implementation for parallel track search pattern
    }

    private func performCreepingLineSearch() {
        // Implementation for creeping line search pattern
    }

    func updateCoverage(location: CLLocationCoordinate2D) {
        coverageMap[location] = true
    }
}

// MARK: - SearchPattern

enum SearchPattern {
    case expandingSquare
    case parallelTrack
    case creepingLine
}

// MARK: - CLLocationCoordinate2D+Hashable

extension CLLocationCoordinate2D: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(latitude)
        hasher.combine(longitude)
    }

    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}