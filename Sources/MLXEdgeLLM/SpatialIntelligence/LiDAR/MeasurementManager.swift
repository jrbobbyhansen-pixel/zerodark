// MeasurementManager.swift — Measurement state and persistence

import Foundation
import SwiftUI
import simd

@MainActor
final class MeasurementManager: ObservableObject {
    // Current measurement state
    @Published var isActive = false
    @Published var currentType: MeasurementType = .distance
    @Published var currentPoints: [SIMD3<Float>] = []
    @Published var unit: MeasurementUnit = .imperial  // Default for US

    // Completed measurements for current scan
    @Published var annotations: ScanAnnotations = ScanAnnotations()

    // Visual feedback
    @Published var lastTapPosition: SIMD3<Float>?

    // Reference to current scan
    private var currentScanDir: URL?

    // MARK: - Load/Save

    func loadAnnotations(for scanDir: URL) {
        currentScanDir = scanDir
        let annotationsURL = scanDir.appendingPathComponent("annotations.json")

        if let data = try? Data(contentsOf: annotationsURL),
           let loaded = try? JSONDecoder().decode(ScanAnnotations.self, from: data) {
            annotations = loaded
        } else {
            annotations = ScanAnnotations()
        }
    }

    func saveAnnotations() {
        guard let scanDir = currentScanDir else { return }
        let annotationsURL = scanDir.appendingPathComponent("annotations.json")

        annotations.lastModified = Date()

        if let data = try? JSONEncoder().encode(annotations) {
            try? data.write(to: annotationsURL)
        }
    }

    // MARK: - Measurement Actions

    func startMeasurement(type: MeasurementType) {
        isActive = true
        currentType = type
        currentPoints = []
        lastTapPosition = nil
    }

    func cancelMeasurement() {
        isActive = false
        currentPoints = []
        lastTapPosition = nil
    }

    func addPoint(_ point: SIMD3<Float>) {
        currentPoints.append(point)
        lastTapPosition = point

        // Auto-complete based on type
        switch currentType {
        case .distance, .height:
            if currentPoints.count >= 2 {
                completeMeasurement()
            }

        case .area:
            // Area needs explicit completion (3+ points)
            break
        }
    }

    func completeMeasurement(label: String? = nil) {
        guard canComplete else { return }

        let annotation = MeasurementAnnotation(
            id: UUID(),
            type: currentType,
            points: currentPoints.map { CodableSIMD3($0) },
            timestamp: Date(),
            label: label
        )

        annotations.measurements.append(annotation)
        saveAnnotations()

        // Reset for next measurement
        currentPoints = []
        lastTapPosition = nil
        // Keep isActive true for consecutive measurements
    }

    func deleteMeasurement(_ annotation: MeasurementAnnotation) {
        annotations.measurements.removeAll { $0.id == annotation.id }
        saveAnnotations()
    }

    func deleteAllMeasurements() {
        annotations.measurements.removeAll()
        saveAnnotations()
    }

    // MARK: - Computed Properties

    var canComplete: Bool {
        switch currentType {
        case .distance, .height:
            return currentPoints.count >= 2
        case .area:
            return currentPoints.count >= 3
        }
    }

    var currentMeasurementValue: String? {
        guard currentPoints.count >= 2 else { return nil }

        let tempAnnotation = MeasurementAnnotation(
            id: UUID(),
            type: currentType,
            points: currentPoints.map { CodableSIMD3($0) },
            timestamp: Date()
        )

        return tempAnnotation.displayValue(unit: unit)
    }

    var pointsNeeded: Int {
        switch currentType {
        case .distance, .height: return 2
        case .area: return 3  // Minimum
        }
    }

    var instructionText: String {
        guard isActive else { return "Select measurement type" }

        switch currentType {
        case .distance:
            if currentPoints.isEmpty {
                return "Tap first point"
            } else {
                return "Tap second point"
            }

        case .height:
            if currentPoints.isEmpty {
                return "Tap bottom point"
            } else {
                return "Tap top point"
            }

        case .area:
            if currentPoints.count < 3 {
                return "Tap point \(currentPoints.count + 1) (min 3)"
            } else {
                return "Tap more points or Done"
            }
        }
    }
}
