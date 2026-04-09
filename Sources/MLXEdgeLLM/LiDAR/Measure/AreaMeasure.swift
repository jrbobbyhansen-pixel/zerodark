import SwiftUI

// MARK: - AreaMeasureViewModel

class AreaMeasureViewModel: ObservableObject {
    @Published var points: [CGPoint] = []
    @Published var areas: [Double] = []
    @Published var selectedUnit: UnitArea = .squareMeters
    
    func addPoint(_ point: CGPoint) {
        points.append(point)
        if points.count > 2 {
            calculateArea()
        }
    }
    
    func reset() {
        points = []
        areas = []
    }
    
    private func calculateArea() {
        guard points.count > 2 else { return }
        let polygon = Polygon(points: points)
        let area = polygon.area
        areas.append(area.converted(to: selectedUnit).value)
    }
}

// MARK: - Polygon

struct Polygon {
    let points: [CGPoint]
    
    var area: Measurement<UnitArea> {
        let area = points.enumerated().reduce(0.0) { (acc, element) -> Double in
            let (index, point) = element
            let nextPoint = points[(index + 1) % points.count]
            return acc + (point.x * nextPoint.y) - (nextPoint.x * point.y)
        }
        return Measurement(value: abs(area) / 2.0, unit: .squareMeters)
    }
}

// MARK: - AreaMeasureView

struct AreaMeasureView: View {
    @StateObject private var viewModel = AreaMeasureViewModel()
    
    var body: some View {
        VStack {
            HStack {
                Text("Area Measurement Tool")
                    .font(.headline)
                Spacer()
                Button("Reset") {
                    viewModel.reset()
                }
            }
            .padding()
            
            Canvas { context, size in
                for point in viewModel.points {
                    context.fill(Circle().inset(by: 5), with: .color(.red), at: point)
                }
                for i in 0..<viewModel.points.count - 1 {
                    context.stroke(Path { path in
                        path.move(to: viewModel.points[i])
                        path.addLine(to: viewModel.points[i + 1])
                    }, with: .color(.blue), lineWidth: 2)
                }
                if viewModel.points.count > 2 {
                    context.stroke(Path { path in
                        path.move(to: viewModel.points.last!)
                        path.addLine(to: viewModel.points.first!)
                    }, with: .color(.blue), lineWidth: 2)
                }
            }
            .frame(height: 300)
            .gesture(DragGesture()
                .onEnded { value in
                    viewModel.addPoint(value.location)
                }
            )
            
            List(viewModel.areas, id: \.self) { area in
                Text("\(area, specifier: "%.2f") \(viewModel.selectedUnit.symbol)")
            }
            .padding()
            
            Picker("Unit", selection: $viewModel.selectedUnit) {
                ForEach(UnitArea.allCases, id: \.self) { unit in
                    Text(unit.symbol)
                }
            }
            .pickerStyle(.segmented)
            .padding()
        }
        .padding()
    }
}

// MARK: - Preview

struct AreaMeasureView_Previews: PreviewProvider {
    static var previews: some View {
        AreaMeasureView()
    }
}