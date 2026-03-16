//
//  ARUseCases.swift
//  ZeroDark
//
//  Concrete use cases for LiDAR and AR capabilities.
//  These are the "why would anyone use this" scenarios.
//

import SwiftUI
import ARKit
import RealityKit
import Vision

// MARK: - AR Use Cases Menu

struct ARUseCasesView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Measurement") {
                    NavigationLink {
                        RoomMeasurementView()
                    } label: {
                        UseCaseRow(
                            icon: "ruler",
                            title: "Room Measurement",
                            subtitle: "Scan a room, get dimensions + square footage"
                        )
                    }
                    
                    NavigationLink {
                        FurnitureFitView()
                    } label: {
                        UseCaseRow(
                            icon: "sofa",
                            title: "Will It Fit?",
                            subtitle: "Measure space, check if furniture fits"
                        )
                    }
                    
                    NavigationLink {
                        DistanceMeasureView()
                    } label: {
                        UseCaseRow(
                            icon: "arrow.left.and.right",
                            title: "Quick Measure",
                            subtitle: "Point-to-point distance measurement"
                        )
                    }
                }
                
                Section("Scanning") {
                    NavigationLink {
                        ObjectScanView()
                    } label: {
                        UseCaseRow(
                            icon: "cube.transparent",
                            title: "3D Object Scan",
                            subtitle: "Create 3D model of any object"
                        )
                    }
                    
                    NavigationLink {
                        ReceiptScanView()
                    } label: {
                        UseCaseRow(
                            icon: "doc.text.viewfinder",
                            title: "Receipt Scanner",
                            subtitle: "Extract items, prices, totals"
                        )
                    }
                    
                    NavigationLink {
                        BusinessCardScanView()
                    } label: {
                        UseCaseRow(
                            icon: "person.crop.rectangle",
                            title: "Business Card",
                            subtitle: "Extract contact info, add to Contacts"
                        )
                    }
                }
                
                Section("Intelligence") {
                    NavigationLink {
                        ObjectIdentifyView()
                    } label: {
                        UseCaseRow(
                            icon: "questionmark.circle",
                            title: "What Is This?",
                            subtitle: "Point at anything, get identification"
                        )
                    }
                    
                    NavigationLink {
                        PlantIdentifyView()
                    } label: {
                        UseCaseRow(
                            icon: "leaf",
                            title: "Plant ID",
                            subtitle: "Identify plants, get care instructions"
                        )
                    }
                    
                    NavigationLink {
                        FoodScanView()
                    } label: {
                        UseCaseRow(
                            icon: "fork.knife",
                            title: "Food Scanner",
                            subtitle: "Identify food, estimate calories"
                        )
                    }
                }
                
                Section("Real Estate / Construction") {
                    NavigationLink {
                        FloorPlanView()
                    } label: {
                        UseCaseRow(
                            icon: "square.split.2x2",
                            title: "Floor Plan",
                            subtitle: "Scan room, generate floor plan"
                        )
                    }
                    
                    NavigationLink {
                        HomeInspectionView()
                    } label: {
                        UseCaseRow(
                            icon: "house.and.flag",
                            title: "Home Inspection",
                            subtitle: "Document issues with AR annotations"
                        )
                    }
                }
            }
            .navigationTitle("AR Capabilities")
        }
    }
}

struct UseCaseRow: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.cyan)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Room Measurement

struct RoomMeasurementView: View {
    @StateObject private var scanner = RoomScanner()
    
    var body: some View {
        ZStack {
            // AR View would go here
            Color.black.ignoresSafeArea()
            
            VStack {
                Spacer()
                
                if scanner.isScanning {
                    ScanProgressView(progress: scanner.scanProgress)
                }
                
                if let dimensions = scanner.roomDimensions {
                    RoomResultCard(dimensions: dimensions)
                }
                
                HStack(spacing: 20) {
                    Button {
                        scanner.startScan()
                    } label: {
                        Label(scanner.isScanning ? "Scanning..." : "Start Scan", systemImage: "viewfinder")
                            .padding()
                            .background(Color.cyan)
                            .foregroundColor(.black)
                            .cornerRadius(12)
                    }
                    .disabled(scanner.isScanning)
                    
                    if scanner.roomDimensions != nil {
                        Button {
                            scanner.exportResults()
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                                .padding()
                                .background(Color.gray.opacity(0.3))
                                .cornerRadius(12)
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Room Measurement")
    }
}

@MainActor
class RoomScanner: ObservableObject {
    @Published var isScanning = false
    @Published var scanProgress: Double = 0
    @Published var roomDimensions: RoomScanResult?
    
    func startScan() {
        isScanning = true
        
        // Simulate scan
        Task {
            for i in 0..<100 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                scanProgress = Double(i) / 100.0
            }
            
            roomDimensions = RoomScanResult(
                width: 3.65,
                length: 4.20,
                height: 2.44,
                squareMeters: 15.33,
                squareFeet: 165.0,
                walls: [
                    WallMeasurement(name: "North", width: 3.65, height: 2.44),
                    WallMeasurement(name: "South", width: 3.65, height: 2.44),
                    WallMeasurement(name: "East", width: 4.20, height: 2.44),
                    WallMeasurement(name: "West", width: 4.20, height: 2.44)
                ],
                doorways: 1,
                windows: 2
            )
            
            isScanning = false
        }
    }
    
    func exportResults() {
        // Export as PDF or send to Notes
    }
}

struct RoomScanResult {
    let width: Double
    let length: Double
    let height: Double
    let squareMeters: Double
    let squareFeet: Double
    let walls: [WallMeasurement]
    let doorways: Int
    let windows: Int
}

struct WallMeasurement {
    let name: String
    let width: Double
    let height: Double
}

struct ScanProgressView: View {
    let progress: Double
    
    var body: some View {
        VStack(spacing: 8) {
            ProgressView(value: progress)
                .tint(.cyan)
            
            Text("Scanning room... \(Int(progress * 100))%")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding()
    }
}

struct RoomResultCard: View {
    let dimensions: RoomScanResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Room Dimensions")
                .font(.system(size: 18, weight: .bold))
            
            HStack(spacing: 30) {
                DimensionStat(label: "Width", value: "\(String(format: "%.1f", dimensions.width))m")
                DimensionStat(label: "Length", value: "\(String(format: "%.1f", dimensions.length))m")
                DimensionStat(label: "Height", value: "\(String(format: "%.1f", dimensions.height))m")
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading) {
                    Text("\(String(format: "%.1f", dimensions.squareMeters)) m²")
                        .font(.system(size: 28, weight: .bold))
                    Text("\(String(format: "%.0f", dimensions.squareFeet)) sq ft")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("\(dimensions.doorways) door")
                    Text("\(dimensions.windows) windows")
                }
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .padding()
    }
}

struct DimensionStat: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .semibold))
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Will It Fit?

struct FurnitureFitView: View {
    @State private var selectedFurniture: FurnitureItem?
    @State private var spaceWidth: String = ""
    @State private var spaceDepth: String = ""
    @State private var spaceHeight: String = ""
    @State private var fitResult: FitResult?
    
    let commonFurniture: [FurnitureItem] = [
        FurnitureItem(name: "Queen Bed", width: 1.53, depth: 2.03, height: 0.6),
        FurnitureItem(name: "King Bed", width: 1.93, depth: 2.03, height: 0.6),
        FurnitureItem(name: "3-Seat Sofa", width: 2.1, depth: 0.9, height: 0.85),
        FurnitureItem(name: "Dining Table (6)", width: 1.8, depth: 0.9, height: 0.75),
        FurnitureItem(name: "Desk", width: 1.5, depth: 0.75, height: 0.75),
        FurnitureItem(name: "Wardrobe", width: 1.2, depth: 0.6, height: 2.0),
        FurnitureItem(name: "Refrigerator", width: 0.9, depth: 0.7, height: 1.8),
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Furniture selector
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Furniture")
                        .font(.headline)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(commonFurniture) { item in
                                FurnitureChip(
                                    item: item,
                                    isSelected: selectedFurniture?.id == item.id
                                ) {
                                    selectedFurniture = item
                                }
                            }
                        }
                    }
                }
                
                // Space input (or AR scan)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Available Space")
                            .font(.headline)
                        
                        Spacer()
                        
                        Button("Scan with AR") {
                            // Would launch AR scanner
                        }
                        .font(.system(size: 14))
                        .foregroundColor(.cyan)
                    }
                    
                    HStack(spacing: 12) {
                        DimensionInput(label: "Width", value: $spaceWidth, unit: "m")
                        DimensionInput(label: "Depth", value: $spaceDepth, unit: "m")
                        DimensionInput(label: "Height", value: $spaceHeight, unit: "m")
                    }
                }
                
                // Check fit button
                Button {
                    checkFit()
                } label: {
                    Text("Check Fit")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.cyan)
                        .cornerRadius(12)
                }
                .disabled(selectedFurniture == nil)
                
                // Result
                if let result = fitResult {
                    FitResultView(result: result)
                }
            }
            .padding()
        }
        .navigationTitle("Will It Fit?")
    }
    
    func checkFit() {
        guard let furniture = selectedFurniture,
              let width = Double(spaceWidth),
              let depth = Double(spaceDepth),
              let height = Double(spaceHeight) else { return }
        
        let widthFits = furniture.width <= width
        let depthFits = furniture.depth <= depth
        let heightFits = furniture.height <= height
        
        // Check if it fits rotated
        let rotatedFits = furniture.depth <= width && furniture.width <= depth
        
        fitResult = FitResult(
            furniture: furniture,
            fits: widthFits && depthFits && heightFits,
            fitsRotated: rotatedFits && heightFits,
            clearance: (
                width: width - furniture.width,
                depth: depth - furniture.depth,
                height: height - furniture.height
            )
        )
    }
}

struct FurnitureItem: Identifiable {
    let id = UUID()
    let name: String
    let width: Double
    let depth: Double
    let height: Double
}

struct FurnitureChip: View {
    let item: FurnitureItem
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(item.name)
                    .font(.system(size: 14, weight: .medium))
                
                Text("\(String(format: "%.1f", item.width))×\(String(format: "%.1f", item.depth))m")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color.cyan : Color.gray.opacity(0.2))
            .foregroundColor(isSelected ? .black : .primary)
            .cornerRadius(10)
        }
    }
}

struct DimensionInput: View {
    let label: String
    @Binding var value: String
    let unit: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            HStack(spacing: 4) {
                TextField("0.0", text: $value)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                
                Text(unit)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct FitResult {
    let furniture: FurnitureItem
    let fits: Bool
    let fitsRotated: Bool
    let clearance: (width: Double, depth: Double, height: Double)
}

struct FitResultView: View {
    let result: FitResult
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: result.fits ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(result.fits ? .green : .red)
                
                VStack(alignment: .leading) {
                    Text(result.fits ? "It Fits!" : "Won't Fit")
                        .font(.system(size: 24, weight: .bold))
                    
                    if !result.fits && result.fitsRotated {
                        Text("But it fits if rotated 90°")
                            .foregroundColor(.orange)
                    }
                }
            }
            
            if result.fits {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Clearance")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 20) {
                        ClearanceItem(label: "Width", value: result.clearance.width)
                        ClearanceItem(label: "Depth", value: result.clearance.depth)
                        ClearanceItem(label: "Height", value: result.clearance.height)
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
    }
}

struct ClearanceItem: View {
    let label: String
    let value: Double
    
    var body: some View {
        VStack(spacing: 2) {
            Text("+\(String(format: "%.1f", value * 100))cm")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(value > 0.1 ? .green : .orange)
            
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Object Identification

struct ObjectIdentifyView: View {
    @StateObject private var identifier = ObjectIdentifier()
    
    var body: some View {
        ZStack {
            // Camera view would go here
            Color.black.ignoresSafeArea()
            
            VStack {
                Spacer()
                
                if let result = identifier.currentResult {
                    IdentificationResultCard(result: result)
                }
                
                Text("Point camera at any object")
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .navigationTitle("What Is This?")
    }
}

@MainActor
class ObjectIdentifier: ObservableObject {
    @Published var currentResult: IdentificationResult?
    
    func identify(image: CGImage) async throws {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        
        guard let observations = request.results?.prefix(5) else { return }
        
        currentResult = IdentificationResult(
            name: observations.first?.identifier ?? "Unknown",
            confidence: observations.first?.confidence ?? 0,
            alternatives: observations.dropFirst().map { $0.identifier }
        )
    }
}

struct IdentificationResult {
    let name: String
    let confidence: Float
    let alternatives: [String]
}

struct IdentificationResultCard: View {
    let result: IdentificationResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(result.name.capitalized)
                    .font(.system(size: 24, weight: .bold))
                
                Spacer()
                
                Text("\(Int(result.confidence * 100))%")
                    .foregroundColor(.secondary)
            }
            
            if !result.alternatives.isEmpty {
                Text("Also could be: \(result.alternatives.joined(separator: ", "))")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .padding()
    }
}

// Placeholder views for other use cases
struct DistanceMeasureView: View { var body: some View { Text("Distance Measure") } }
struct ObjectScanView: View { var body: some View { Text("Object Scan") } }
struct ReceiptScanView: View { var body: some View { Text("Receipt Scan") } }
struct BusinessCardScanView: View { var body: some View { Text("Business Card Scan") } }
struct PlantIdentifyView: View { var body: some View { Text("Plant ID") } }
struct FoodScanView: View { var body: some View { Text("Food Scan") } }
struct FloorPlanView: View { var body: some View { Text("Floor Plan") } }
struct HomeInspectionView: View { var body: some View { Text("Home Inspection") } }

#Preview {
    ARUseCasesView()
}
