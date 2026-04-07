import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - CotGenerator

class CotGenerator: ObservableObject {
    @Published var positionMessage: String?
    @Published var markerMessage: String?
    @Published var shapeMessage: String?
    @Published var sensorMessage: String?
    
    func generatePositionMessage(location: CLLocationCoordinate2D, uid: String) {
        let timestamp = Date().cotTimestamp
        let message = """
        <event version="2.0" uid="\(uid)" type="t" time="\(timestamp)" start="\(timestamp)" stale="\(timestamp.addingTimeInterval(3600))" how="h-g-i-g-o">
            <point lat="\(location.latitude)" lon="\(location.longitude)" hae="0.0" ce="0.0" le="0.0"/>
        </event>
        """
        positionMessage = message
    }
    
    func generateMarkerMessage(location: CLLocationCoordinate2D, uid: String, name: String) {
        let timestamp = Date().cotTimestamp
        let message = """
        <event version="2.0" uid="\(uid)" type="a-f-G-U-C" time="\(timestamp)" start="\(timestamp)" stale="\(timestamp.addingTimeInterval(3600))" how="h-g-i-g-o">
            <point lat="\(location.latitude)" lon="\(location.longitude)" hae="0.0" ce="0.0" le="0.0"/>
            <detail>
                <iconString>mil_std_icon_150</iconString>
                <name>\(name)</name>
            </detail>
        </event>
        """
        markerMessage = message
    }
    
    func generateShapeMessage(location: CLLocationCoordinate2D, uid: String, shapeType: String) {
        let timestamp = Date().cotTimestamp
        let message = """
        <event version="2.0" uid="\(uid)" type="a-f-G-U-C" time="\(timestamp)" start="\(timestamp)" stale="\(timestamp.addingTimeInterval(3600))" how="h-g-i-g-o">
            <point lat="\(location.latitude)" lon="\(location.longitude)" hae="0.0" ce="0.0" le="0.0"/>
            <detail>
                <iconString>mil_std_icon_150</iconString>
                <name>\(shapeType)</name>
            </detail>
        </event>
        """
        shapeMessage = message
    }
    
    func generateSensorMessage(location: CLLocationCoordinate2D, uid: String, sensorType: String) {
        let timestamp = Date().cotTimestamp
        let message = """
        <event version="2.0" uid="\(uid)" type="a-f-G-U-C" time="\(timestamp)" start="\(timestamp)" stale="\(timestamp.addingTimeInterval(3600))" how="h-g-i-g-o">
            <point lat="\(location.latitude)" lon="\(location.longitude)" hae="0.0" ce="0.0" le="0.0"/>
            <detail>
                <iconString>mil_std_icon_150</iconString>
                <name>\(sensorType)</name>
            </detail>
        </event>
        """
        sensorMessage = message
    }
}

// MARK: - Date Extension

extension Date {
    var cotTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: self)
    }
}