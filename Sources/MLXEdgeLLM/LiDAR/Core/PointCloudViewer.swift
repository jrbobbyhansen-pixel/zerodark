import SwiftUI
import MetalKit
import ARKit
import CoreLocation

struct PointCloudViewer: View {
    @StateObject private var viewModel = PointCloudViewModel()
    
    var body: some View {
        MetalView(device: viewModel.device, in: viewModel.commandQueue)
            .ignoresSafeArea()
            .environmentObject(viewModel)
    }
}

class PointCloudViewModel: ObservableObject {
    @Published var device: MTLDevice
    @Published var commandQueue: MTLCommandQueue
    @Published var pointCloud: [ARPoint] = []
    
    init() {
        device = MTLCreateSystemDefaultDevice()!
        commandQueue = device.makeCommandQueue()!
    }
    
    func updatePointCloud(_ newPointCloud: [ARPoint]) {
        pointCloud = newPointCloud
    }
}

struct MetalView: UIViewRepresentable {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    
    func makeUIView(context: Context) -> MTKView {
        let metalView = MTKView(frame: .zero, device: device)
        metalView.delegate = context.coordinator
        metalView.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.depthStencilPixelFormat = .depth32Float
        metalView.sampleCount = 1
        return metalView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        // Update the Metal view if necessary
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(device: device, commandQueue: commandQueue)
    }
    
    class Coordinator: NSObject, MTKViewDelegate {
        let device: MTLDevice
        let commandQueue: MTLCommandQueue
        var renderPipelineState: MTLRenderPipelineState?
        
        init(device: MTLDevice, commandQueue: MTLCommandQueue) {
            self.device = device
            self.commandQueue = commandQueue
            super.init()
            createRenderPipelineState()
        }
        
        func createRenderPipelineState() {
            let library = device.makeDefaultLibrary()!
            let vertexFunction = library.makeFunction(name: "vertex_main")!
            let fragmentFunction = library.makeFunction(name: "fragment_main")!
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
            
            do {
                renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            } catch {
                print("Failed to create render pipeline state: \(error)")
            }
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // Handle drawable size change
        }
        
        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let renderPassDescriptor = view.currentRenderPassDescriptor,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                return
            }
            
            renderEncoder.setRenderPipelineState(renderPipelineState!)
            // Set vertex buffers, textures, etc.
            renderEncoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}