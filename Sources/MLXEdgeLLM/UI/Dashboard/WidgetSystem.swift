import SwiftUI
import Combine

// MARK: - WidgetSystem

struct WidgetSystem: View {
    @StateObject private var viewModel = WidgetViewModel()
    
    var body: some View {
        VStack {
            HStack {
                Text("Dashboard")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
                Button(action: viewModel.addNewWidget) {
                    Image(systemName: "plus.circle")
                        .font(.title)
                }
            }
            .padding()
            
            ScrollView {
                LazyVGrid(columns: viewModel.gridColumns, spacing: 16) {
                    ForEach(viewModel.widgets) { widget in
                        WidgetView(widget: widget)
                            .frame(width: widget.size.width, height: widget.size.height)
                            .onDrag {
                                NSItemProvider(object: widget.id as NSString)
                            }
                            .onDrop(of: [.string], delegate: DropDelegate(widget: widget, viewModel: viewModel))
                    }
                }
                .padding()
            }
        }
        .padding()
    }
}

// MARK: - WidgetViewModel

class WidgetViewModel: ObservableObject {
    @Published var widgets: [Widget] = []
    @Published var gridColumns: [GridItem] = [GridItem(.flexible()), GridItem(.flexible())]
    
    init() {
        // Load initial widgets
        widgets = [
            Widget(id: UUID(), type: .map, size: CGSize(width: 200, height: 200)),
            Widget(id: UUID(), type: .camera, size: CGSize(width: 200, height: 200))
        ]
    }
    
    func addNewWidget() {
        let newWidget = Widget(id: UUID(), type: .info, size: CGSize(width: 200, height: 200))
        widgets.append(newWidget)
    }
}

// MARK: - Widget

struct Widget: Identifiable {
    let id: UUID
    let type: WidgetType
    var size: CGSize
}

// MARK: - WidgetType

enum WidgetType {
    case map
    case camera
    case info
}

// MARK: - WidgetView

struct WidgetView: View {
    let widget: Widget
    
    var body: some View {
        switch widget.type {
        case .map:
            $name()
        case .camera:
            CameraView()
        case .info:
            InfoView()
        }
    }
}

// MARK: - MapView

struct WidgetMapSnippet: View {
    var body: some View {
        Map()
            .edgesIgnoringSafeArea(.all)
    }
}

// MARK: - CameraView

struct CameraView: View {
    var body: some View {
        Text("Camera View")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.blue)
    }
}

// MARK: - InfoView

struct InfoView: View {
    var body: some View {
        Text("Info View")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.green)
    }
}

// MARK: - DropDelegate

struct DropDelegate: DropDelegate {
    let widget: Widget
    let viewModel: WidgetViewModel
    
    func performDrop(info: DropInfo) -> Bool {
        // Handle drop logic
        return true
    }
}