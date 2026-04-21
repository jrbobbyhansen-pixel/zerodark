// ScanOverlayRenderer.swift — Build SCNNodes for ScanOverlays, attach to a scene.
//
// Mirrors the Terrain3DOverlays pattern (name-prefix based, rebuilt on state change).
// Node naming convention: "scanoverlay_<uuid>" — lets the tap-handler distinguish
// overlay hits from point-cloud hits.

import Foundation
import SceneKit
import simd
import UIKit

@MainActor
enum ScanOverlayRenderer {

    static let nodeNamePrefix = "scanoverlay_"

    /// Remove all overlay nodes from the scene root, then re-add from the current store state.
    static func rebuild(for scanID: UUID, in scene: SCNScene) {
        let root = scene.rootNode
        root.childNodes
            .filter { $0.name?.hasPrefix(nodeNamePrefix) == true }
            .forEach { $0.removeFromParentNode() }

        let list = ScanOverlayStore.shared.list(for: scanID)
        for overlay in list {
            let node = makeNode(for: overlay)
            node.name = "\(nodeNamePrefix)\(overlay.id.uuidString)"
            root.addChildNode(node)
        }
    }

    /// Add a single pending-placement preview node (used while user is mid-tap for walls / zones).
    static func addPreviewPoint(_ point: SIMD3<Float>, kind: ScanOverlayKind, in scene: SCNScene) {
        let sphere = SCNSphere(radius: 0.12)
        let mat = SCNMaterial()
        mat.diffuse.contents = uiColor(for: kind, alpha: 0.9)
        mat.lightingModel = .constant
        sphere.materials = [mat]
        let node = SCNNode(geometry: sphere)
        node.position = SCNVector3(point.x, point.y, point.z)
        node.name = "\(nodeNamePrefix)preview"
        scene.rootNode.addChildNode(node)
    }

    /// Remove any preview-in-progress nodes (unfinalized tap markers).
    static func clearPreviews(in scene: SCNScene) {
        scene.rootNode.childNodes
            .filter { $0.name == "\(nodeNamePrefix)preview" }
            .forEach { $0.removeFromParentNode() }
    }

    // MARK: - Node construction

    private static func makeNode(for overlay: ScanOverlay) -> SCNNode {
        switch overlay.kind {
        case .wall:      return wallNode(overlay)
        case .door:      return doorNode(overlay)
        case .window:    return windowNode(overlay)
        case .zone:      return zoneNode(overlay)
        case .hazard:    return markerNode(overlay, shape: .sphere, pulse: true)
        case .cover:     return markerNode(overlay, shape: .cone, pulse: false)
        case .entry:     return markerNode(overlay, shape: .pyramid, pulse: false)
        case .objective: return markerNode(overlay, shape: .sphere, pulse: false)
        }
    }

    private enum MarkerShape { case sphere, cone, pyramid }

    private static func markerNode(_ overlay: ScanOverlay, shape: MarkerShape, pulse: Bool) -> SCNNode {
        let geo: SCNGeometry
        switch shape {
        case .sphere:  geo = SCNSphere(radius: 0.18)
        case .cone:    geo = SCNCone(topRadius: 0, bottomRadius: 0.22, height: 0.55)
        case .pyramid: geo = SCNPyramid(width: 0.35, height: 0.5, length: 0.35)
        }
        let mat = SCNMaterial()
        mat.diffuse.contents = uiColor(for: overlay.kind, alpha: 1.0)
        mat.lightingModel = .constant
        geo.materials = [mat]

        let node = SCNNode(geometry: geo)
        node.position = SCNVector3(overlay.anchor.x, overlay.anchor.y, overlay.anchor.z)

        if pulse {
            let grow = SCNAction.scale(to: 1.35, duration: 0.6)
            let shrink = SCNAction.scale(to: 1.0, duration: 0.6)
            grow.timingMode = .easeInEaseOut
            shrink.timingMode = .easeInEaseOut
            node.runAction(.repeatForever(.sequence([grow, shrink])))
        }
        return node
    }

    /// Wall: thin vertical slab between the two anchor points. Default height 2.5 m.
    private static func wallNode(_ overlay: ScanOverlay) -> SCNNode {
        let pts = overlay.simdPoints
        guard pts.count >= 2 else { return SCNNode() }
        let a = pts[0]
        let b = pts[1]

        let dx = b.x - a.x
        let dz = b.z - a.z
        let length = sqrt(dx * dx + dz * dz)
        guard length > 0.01 else { return SCNNode() }

        let height: CGFloat = 2.5
        let box = SCNBox(width: CGFloat(length), height: height, length: 0.08, chamferRadius: 0)
        let mat = SCNMaterial()
        mat.diffuse.contents = uiColor(for: .wall, alpha: 0.55)
        mat.isDoubleSided = true
        mat.lightingModel = .constant
        box.materials = [mat]

        let node = SCNNode(geometry: box)
        // Midpoint, half-height up on Y
        let midX = (a.x + b.x) / 2
        let midZ = (a.z + b.z) / 2
        let midY = (a.y + b.y) / 2 + Float(height / 2)
        node.position = SCNVector3(midX, midY, midZ)

        // Rotate around Y so the box width aligns with segment direction in the XZ plane
        let angle = atan2(dz, dx)
        node.eulerAngles = SCNVector3(0, -angle, 0)
        return node
    }

    /// Door: 0.9m × 2.1m plane, rotated by overlay.rotationY around Y.
    private static func doorNode(_ overlay: ScanOverlay) -> SCNNode {
        let plane = SCNPlane(width: 0.9, height: 2.1)
        let mat = SCNMaterial()
        mat.diffuse.contents = uiColor(for: .door, alpha: 0.75)
        mat.isDoubleSided = true
        mat.lightingModel = .constant
        plane.materials = [mat]
        let node = SCNNode(geometry: plane)
        let p = overlay.anchor
        node.position = SCNVector3(p.x, p.y + 1.05, p.z)
        node.eulerAngles = SCNVector3(0, overlay.rotationY, 0)
        return node
    }

    /// Window: 1.2m × 1.0m plane, rotated by overlay.rotationY around Y.
    private static func windowNode(_ overlay: ScanOverlay) -> SCNNode {
        let plane = SCNPlane(width: 1.2, height: 1.0)
        let mat = SCNMaterial()
        mat.diffuse.contents = uiColor(for: .window, alpha: 0.55)
        mat.isDoubleSided = true
        mat.lightingModel = .constant
        plane.materials = [mat]
        let node = SCNNode(geometry: plane)
        let p = overlay.anchor
        // Default window height: 1.2m above ground. p.y is the tapped point; raise it.
        node.position = SCNVector3(p.x, p.y + 0.6, p.z)
        node.eulerAngles = SCNVector3(0, overlay.rotationY, 0)
        return node
    }

    /// Zone: flat polygon in the XZ plane at the (average) Y of the tapped points.
    /// Uses SCNShape built from a UIBezierPath of the polygon.
    private static func zoneNode(_ overlay: ScanOverlay) -> SCNNode {
        let pts = overlay.simdPoints
        guard pts.count >= 3 else { return SCNNode() }

        let avgY = pts.reduce(Float(0)) { $0 + $1.y } / Float(pts.count)

        let path = UIBezierPath()
        path.move(to: CGPoint(x: CGFloat(pts[0].x), y: CGFloat(pts[0].z)))
        for p in pts.dropFirst() {
            path.addLine(to: CGPoint(x: CGFloat(p.x), y: CGFloat(p.z)))
        }
        path.close()

        let shape = SCNShape(path: path, extrusionDepth: 0.01)
        let mat = SCNMaterial()
        mat.diffuse.contents = uiColor(for: .zone, alpha: 0.30)
        mat.isDoubleSided = true
        mat.lightingModel = .constant
        shape.materials = [mat]

        let node = SCNNode(geometry: shape)
        // SCNShape is authored in XY; rotate so its plane lies on XZ (ground).
        node.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        node.position = SCNVector3(0, avgY + 0.005, 0)
        return node
    }

    // MARK: - Colors

    static func uiColor(for kind: ScanOverlayKind, alpha: CGFloat) -> UIColor {
        let base: UIColor
        switch kind {
        case .wall:      base = UIColor(red: 0.424, green: 0.459, blue: 0.490, alpha: 1)  // mediumGray
        case .door:      base = UIColor(red: 0.133, green: 0.827, blue: 0.933, alpha: 1)  // cyanAccent
        case .window:    base = UIColor(red: 0.290, green: 0.565, blue: 0.643, alpha: 1)  // skyBlue
        case .zone:      base = UIColor(red: 1.000, green: 0.843, blue: 0.000, alpha: 1)  // safetyYellow
        case .hazard:    base = UIColor(red: 1.000, green: 0.267, blue: 0.267, alpha: 1)  // signalRed
        case .cover:     base = UIColor(red: 0.176, green: 0.314, blue: 0.086, alpha: 1)  // forestGreen
        case .entry:     base = UIColor(red: 0.157, green: 0.655, blue: 0.271, alpha: 1)  // successGreen
        case .objective: base = UIColor(red: 0.133, green: 0.827, blue: 0.933, alpha: 1)  // cyanAccent
        }
        return base.withAlphaComponent(alpha)
    }
}
