// CameraAnnotationView.swift — Directional camera marker for map

import SwiftUI
import MapKit

// MARK: - Camera Annotation View

struct CameraAnnotationView: View {
    let camera: TrafficCamera
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Field of view cone (if heading known)
                if let heading = camera.heading {
                    CameraFOVCone(
                        heading: heading,
                        fov: camera.fieldOfView ?? 90
                    )
                    .fill(isSelected ? ZDDesign.cyanAccent.opacity(0.3) : Color.white.opacity(0.15))
                    .frame(width: 60, height: 60)
                }

                // Camera icon
                ZStack {
                    Circle()
                        .fill(isSelected ? ZDDesign.cyanAccent : ZDDesign.darkCard)
                        .frame(width: 28, height: 28)

                    Circle()
                        .stroke(isSelected ? ZDDesign.cyanAccent : Color.white.opacity(0.5), lineWidth: 2)
                        .frame(width: 28, height: 28)

                    Image(systemName: "video.fill")
                        .font(.system(size: 12))
                        .foregroundColor(isSelected ? .black : .white)
                }
            }
        }
    }
}

// MARK: - Field of view cone shape

struct CameraFOVCone: Shape {
    let heading: Double  // degrees from north
    let fov: Double      // field of view in degrees

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        // Convert to radians (heading 0 = north = -90° in standard coords)
        let startAngle = Angle(degrees: heading - fov / 2 - 90)
        let endAngle = Angle(degrees: heading + fov / 2 - 90)

        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.closeSubpath()

        return path
    }
}

// MARK: - Map Annotation Class

class CameraMapAnnotation: NSObject, MKAnnotation {
    let camera: TrafficCamera
    dynamic var coordinate: CLLocationCoordinate2D {
        camera.coordinate
    }

    var title: String? {
        camera.displayName
    }

    init(camera: TrafficCamera) {
        self.camera = camera
        super.init()
    }
}
