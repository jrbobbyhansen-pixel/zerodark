// DeepLinkRouter.swift — Parse zerodark:// URLs into typed app actions.
//
// Roadmap PR-C4. Apps that ship without a URL scheme router end up with
// a thicket of ad-hoc `if url.host == "map"` checks scattered across
// onOpenURL handlers. This file gives us one place to keep the grammar:
//
//   zerodark://map?lat=35.2&lon=-118.5&zoom=12
//   zerodark://lidar/scan/<uuid>
//   zerodark://mesh/peer/<callsign>
//   zerodark://ops
//   zerodark://intel?mode=knowledge
//
// Parse results are a DeepLinkAction enum the App layer can dispatch
// without touching URL internals. Unknown or malformed URLs return
// `.none` so callers can fall back to opening the default tab.

import Foundation
import CoreLocation

public enum DeepLinkAction: Equatable {
    case none
    case openMap(center: CLLocationCoordinate2D?, zoom: Double?)
    case openLiDARScan(id: UUID)
    case openMeshPeer(callsign: String)
    case openOps
    case openIntel(mode: String?)
    case openNav
}

extension DeepLinkAction {
    public static func == (lhs: DeepLinkAction, rhs: DeepLinkAction) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none), (.openOps, .openOps), (.openNav, .openNav):
            return true
        case (.openMap(let c1, let z1), .openMap(let c2, let z2)):
            return coordEq(c1, c2) && z1 == z2
        case (.openLiDARScan(let a), .openLiDARScan(let b)):
            return a == b
        case (.openMeshPeer(let a), .openMeshPeer(let b)):
            return a == b
        case (.openIntel(let a), .openIntel(let b)):
            return a == b
        default:
            return false
        }
    }

    private static func coordEq(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (let x?, let y?): return x.latitude == y.latitude && x.longitude == y.longitude
        default: return false
        }
    }
}

public enum DeepLinkRouter {
    /// Parse a zerodark://... URL into a dispatchable action. Returns
    /// `.none` for foreign schemes, unknown hosts, or malformed paths.
    public static func parse(_ url: URL) -> DeepLinkAction {
        guard url.scheme?.lowercased() == "zerodark" else { return .none }
        guard let host = url.host?.lowercased() else { return .none }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = components?.queryItems ?? []
        // Drop the leading "/" and split path segments.
        let pathSegments = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "map":
            let lat  = query.first(where: { $0.name == "lat"  }).flatMap { $0.value }.flatMap(Double.init)
            let lon  = query.first(where: { $0.name == "lon"  }).flatMap { $0.value }.flatMap(Double.init)
            let zoom = query.first(where: { $0.name == "zoom" }).flatMap { $0.value }.flatMap(Double.init)
            let coord: CLLocationCoordinate2D? = (lat != nil && lon != nil)
                ? CLLocationCoordinate2D(latitude: lat!, longitude: lon!)
                : nil
            return .openMap(center: coord, zoom: zoom)

        case "lidar":
            // zerodark://lidar/scan/<uuid>
            if pathSegments.count >= 2, pathSegments[0] == "scan",
               let uuid = UUID(uuidString: pathSegments[1]) {
                return .openLiDARScan(id: uuid)
            }
            return .none

        case "mesh":
            // zerodark://mesh/peer/<callsign>
            if pathSegments.count >= 2, pathSegments[0] == "peer" {
                let callsign = pathSegments[1]
                if !callsign.isEmpty {
                    return .openMeshPeer(callsign: callsign)
                }
            }
            return .none

        case "ops":
            return .openOps

        case "intel":
            let mode = query.first(where: { $0.name == "mode" })?.value
            return .openIntel(mode: mode)

        case "nav":
            return .openNav

        default:
            return .none
        }
    }
}
