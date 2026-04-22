// MGRSGridLines.swift — Pure geometry helper for MGRS grid overlay.
//
// Extracted from App/MapTabView.swift (PR-B6) so the same computation can
// be reused in Navigation tab / AR views and covered by unit tests that
// don't need SwiftUI or MapKit state. Does NOT format as MGRS strings —
// that conversion lives in Navigation/MGRSConverter.swift. This file only
// emits lat/lon polylines whose spacing is based on the visible region.

import Foundation
import CoreLocation
import MapKit

public enum MGRSGridLines {
    /// Compute grid polylines spanning `region` at a spacing that fits
    /// the zoom level. Returns one polyline per gridline as an array of
    /// two endpoints (south→north for verticals, west→east for horizontals).
    public static func gridLines(for region: MKCoordinateRegion) -> [[CLLocationCoordinate2D]] {
        let spacing = spacing(for: region)
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2

        var lines: [[CLLocationCoordinate2D]] = []

        // Vertical lines — constant longitude, span latitude range
        var lon = (minLon / spacing).rounded(.down) * spacing
        while lon <= maxLon {
            lines.append([
                CLLocationCoordinate2D(latitude: minLat, longitude: lon),
                CLLocationCoordinate2D(latitude: maxLat, longitude: lon)
            ])
            lon += spacing
        }

        // Horizontal lines — constant latitude, span longitude range
        var lat = (minLat / spacing).rounded(.down) * spacing
        while lat <= maxLat {
            lines.append([
                CLLocationCoordinate2D(latitude: lat, longitude: minLon),
                CLLocationCoordinate2D(latitude: lat, longitude: maxLon)
            ])
            lat += spacing
        }

        return lines
    }

    /// Grid spacing (in degrees) chosen from the wider of the two region
    /// spans. Breakpoints match the original implementation so the visual
    /// behavior is unchanged after extraction.
    public static func spacing(for region: MKCoordinateRegion) -> Double {
        let span = max(region.span.latitudeDelta, region.span.longitudeDelta)
        if span > 10   { return 6.0 }
        if span > 1    { return 1.0 }
        if span > 0.1  { return 0.1 }
        return 0.01
    }
}
