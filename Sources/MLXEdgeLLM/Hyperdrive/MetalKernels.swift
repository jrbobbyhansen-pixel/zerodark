import Foundation
import Metal

// MARK: - Custom Metal Kernels

/// Hand-optimized Metal compute shaders for maximum M-series performance
/// Exploits Apple Silicon's unified memory architecture

public final class MetalKernels {
    
    public static let shared = MetalKernels()
    
    // MARK: - Device Info
    
    public struct DeviceCapabilities {
        public let name: String
        public let maxThreadsPerGroup: Int
        public let maxMemoryBandwidthGBps: Float
        public let neuralEngineOps: Float  // TOPS
        public let gpuCores: Int
        
        public static func detect() -> DeviceCapabilities {
            guard let device = MTLCreateSystemDefaultDevice() else {
                return DeviceCapabilities(
                    name: "Unknown",
                    maxThreadsPerGroup: 256,
                    maxMemoryBandwidthGBps: 50,
                    neuralEngineOps: 0,
                    gpuCores: 8
                )
            }
            
            let name = device.name
            let maxThreads = device.maxThreadsPerThreadgroup.width
            
            // Estimated based on chip
            let (bandwidth, ane, cores) = estimateChipCapabilities(name: name)
            
            return DeviceCapabilities(
                name: name,
                maxThreadsPerGroup: maxThreads,
                maxMemoryBandwidthGBps: bandwidth,
                neuralEngineOps: ane,
                gpuCores: cores
            )
        }
        
        private static func estimateChipCapabilities(name: String) -> (Float, Float, Int) {
            // Memory bandwidth, ANE TOPS, GPU cores
            if name.contains("M4 Max") { return (546, 38, 40) }
            if name.contains("M4 Pro") { return (273, 38, 20) }
            if name.contains("M4") { return (120, 38, 10) }
            if name.contains("M3 Max") { return (400, 18, 40) }
            if name.contains("M3 Pro") { return (200, 18, 18) }
            if name.contains("M3") { return (100, 18, 10) }
            if name.contains("M2 Ultra") { return (800, 31, 76) }
            if name.contains("M2 Max") { return (400, 15.8, 38) }
            if name.contains("M2 Pro") { return (200, 15.8, 19) }
            if name.contains("M2") { return (100, 15.8, 10) }
            if name.contains("M1 Ultra") { return (800, 22, 64) }
            if name.contains("M1 Max") { return (400, 11, 32) }
            if name.contains("M1 Pro") { return (200, 11, 16) }
            if name.contains("M1") { return (68, 11, 8) }
            if name.contains("A17") { return (100, 35, 6) }  // iPhone 15 Pro
            if name.contains("A18") { return (120, 38, 6) }  // iPhone 16
            return (50, 8, 4) // Conservative default
        }
    }
    
    public let capabilities: DeviceCapabilities
    
    // MARK: - Metal Resources
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var kernels: [String: MTLComputePipelineState] = [:]
    
    private init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            fatalError("Metal not available")
        }
        
        self.device = device
        self.commandQueue = queue
        self.capabilities = DeviceCapabilities.detect()
        
        compileKernels()
    }
    
    // MARK: - Kernel Compilation
    
    private func compileKernels() {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        
        // Fused GEMM + GELU activation
        // Combines matrix multiply with activation in single kernel
        // Avoids memory round-trip
        kernel void fused_gemm_gelu(
            device const half* A [[buffer(0)]],
            device const half* B [[buffer(1)]],
            device half* C [[buffer(2)]],
            constant uint& M [[buffer(3)]],
            constant uint& N [[buffer(4)]],
            constant uint& K [[buffer(5)]],
            uint2 gid [[thread_position_in_grid]])
        {
            if (gid.x >= N || gid.y >= M) return;
            
            float sum = 0.0f;
            for (uint k = 0; k < K; k++) {
                sum += float(A[gid.y * K + k]) * float(B[k * N + gid.x]);
            }
            
            // GELU approximation
            float x = sum;
            float gelu = 0.5f * x * (1.0f + tanh(0.7978845608f * (x + 0.044715f * x * x * x)));
            
            C[gid.y * N + gid.x] = half(gelu);
        }
        
        // Fused RMSNorm
        kernel void rms_norm(
            device const half* input [[buffer(0)]],
            device const half* weight [[buffer(1)]],
            device half* output [[buffer(2)]],
            constant uint& dim [[buffer(3)]],
            constant float& eps [[buffer(4)]],
            uint tid [[thread_position_in_grid]])
        {
            float sum_sq = 0.0f;
            for (uint i = 0; i < dim; i++) {
                float val = float(input[tid * dim + i]);
                sum_sq += val * val;
            }
            
            float rms = rsqrt(sum_sq / float(dim) + eps);
            
            for (uint i = 0; i < dim; i++) {
                float val = float(input[tid * dim + i]);
                output[tid * dim + i] = half(val * rms * float(weight[i]));
            }
        }
        
        // Rotary Position Embedding (RoPE)
        kernel void rope_embedding(
            device half* query [[buffer(0)]],
            device half* key [[buffer(1)]],
            constant float* cos_cache [[buffer(2)]],
            constant float* sin_cache [[buffer(3)]],
            constant uint& seq_len [[buffer(4)]],
            constant uint& head_dim [[buffer(5)]],
            uint2 gid [[thread_position_in_grid]])
        {
            uint pos = gid.y;
            uint dim_pair = gid.x;
            
            if (dim_pair >= head_dim / 2) return;
            
            float cos_val = cos_cache[pos * head_dim / 2 + dim_pair];
            float sin_val = sin_cache[pos * head_dim / 2 + dim_pair];
            
            uint idx1 = pos * head_dim + dim_pair * 2;
            uint idx2 = idx1 + 1;
            
            // Rotate query
            float q1 = float(query[idx1]);
            float q2 = float(query[idx2]);
            query[idx1] = half(q1 * cos_val - q2 * sin_val);
            query[idx2] = half(q1 * sin_val + q2 * cos_val);
            
            // Rotate key
            float k1 = float(key[idx1]);
            float k2 = float(key[idx2]);
            key[idx1] = half(k1 * cos_val - k2 * sin_val);
            key[idx2] = half(k1 * sin_val + k2 * cos_val);
        }
        
        // Softmax with online normalization
        kernel void online_softmax(
            device half* scores [[buffer(0)]],
            constant uint& seq_len [[buffer(1)]],
            uint tid [[thread_position_in_grid]])
        {
            uint offset = tid * seq_len;
            
            // Find max for numerical stability
            float max_val = -INFINITY;
            for (uint i = 0; i < seq_len; i++) {
                float val = float(scores[offset + i]);
                max_val = max(max_val, val);
            }
            
            // Compute exp and sum
            float sum = 0.0f;
            for (uint i = 0; i < seq_len; i++) {
                float val = exp(float(scores[offset + i]) - max_val);
                scores[offset + i] = half(val);
                sum += val;
            }
            
            // Normalize
            float inv_sum = 1.0f / sum;
            for (uint i = 0; i < seq_len; i++) {
                scores[offset + i] = half(float(scores[offset + i]) * inv_sum);
            }
        }
        """
        
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            
            let kernelNames = ["fused_gemm_gelu", "rms_norm", "rope_embedding", "online_softmax"]
            
            for name in kernelNames {
                if let function = library.makeFunction(name: name) {
                    let pipeline = try device.makeComputePipelineState(function: function)
                    kernels[name] = pipeline
                }
            }
            
            print("[MetalKernels] Compiled \(kernels.count) custom kernels")
            
        } catch {
            print("[MetalKernels] Compilation failed: \(error)")
        }
    }
    
    // MARK: - Performance Estimates
    
    /// Estimated tokens per second for model
    public func estimateTokensPerSecond(model: Model) -> Int {
        let bandwidth = capabilities.maxMemoryBandwidthGBps
        let modelSizeGB = Float(model.approximateSizeMB) / 1000
        
        // Simple bandwidth-bound estimate
        // Each token requires reading full model
        let theoreticalTPS = bandwidth / modelSizeGB
        
        // Apply efficiency factor (memory access patterns, etc.)
        let efficiency: Float = 0.6
        
        return Int(theoreticalTPS * efficiency)
    }
    
    /// Performance by model and device
    public static func performanceMatrix() -> [(Model, String, Int)] {
        let kernels = MetalKernels.shared
        var results: [(Model, String, Int)] = []
        
        for model in [Model.qwen3_4b, .qwen3_8b, .qwen25_14b] {
            let tps = kernels.estimateTokensPerSecond(model: model)
            results.append((model, kernels.capabilities.name, tps))
        }
        
        return results
    }
}
